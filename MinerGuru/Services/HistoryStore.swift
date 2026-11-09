import Foundation
import SQLite3

/// Long-term telemetry in a local SQLite file (MG-08). Every poll goes into a per-minute average; minute rows stay
/// for `minuteRetention`, hourly rollups for `hourRetention`. All work happens on one serial queue.
final class HistoryStore: @unchecked Sendable {
    /// One poll of one miner; `nil` values for a miner that did not answer.
    struct Reading: Sendable {
        var minerID: UUID
        var date: Date
        var isOnline: Bool
        var hashRateGHs: Double = 0
        var asicTempC: Double = 0
        var vrTempC: Double?
        var powerWatts: Double = 0
        var fanPercent: Double = 0
        var poolLatencyMs: Double?
        var errorPercent: Double?
        var sharesAccepted: Int = 0
        var sharesRejected: Int = 0
        var bestDiff: Double = 0
    }

    static let minuteRetention: TimeInterval = 14 * 86_400
    static let hourRetention: TimeInterval = 3 * 365 * 86_400
    /// Charts need no more points than this.
    static let maxPoints = 720

    private struct Bucket {
        var minute: Int
        var polls = 0
        var onlinePolls = 0
        var hashRate = 0.0, temp = 0.0, maxTemp = 0.0, vr = 0.0, vrCount = 0, power = 0.0, fan = 0.0
        var latency = 0.0, latencyCount = 0, error = 0.0, errorCount = 0
        var accepted = 0, rejected = 0
        var best = 0.0
    }

    private let queue = DispatchQueue(label: "app.minerguru.history")
    private let path: String?
    private let migrations: [String]
    private var db: OpaquePointer?
    private var isRecovering = false
    private var buckets: [UUID: Bucket] = [:]
    private var lastCounters: [UUID: (accepted: Int, rejected: Int)] = [:]
    private var lastRollup: Date?
    private var hasRolledUp = false

    /// - Parameter path: SQLite file; `nil` keeps the data in memory (tests).
    /// - Parameter migrations: replaced by tests only.
    init(path: String?, migrations: [String] = HistoryStore.migrations) {
        self.path = path
        self.migrations = migrations
        queue.sync { open() }
    }

    /// The copy of a damaged file, set once one was moved aside.
    private(set) var damagedBackup: String?
    /// Runs on the store's queue after a damaged file was moved aside and the history started over.
    var onDamaged: (@Sendable () -> Void)?

    private func open() {
        if let path {
            try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        }
        guard sqlite3_open(path ?? ":memory:", &db) == SQLITE_OK else {
            Log.app.error("History database not opened")
            db = nil
            return
        }
        exec("PRAGMA journal_mode=WAL")
        exec("PRAGMA synchronous=NORMAL")
        exec("""
            CREATE TABLE IF NOT EXISTS samples(
              resolution INTEGER NOT NULL, miner TEXT NOT NULL, ts INTEGER NOT NULL,
              online INTEGER NOT NULL, total INTEGER NOT NULL,
              hashrate REAL, asic REAL, asic_max REAL, vr REAL, power REAL, fan REAL, latency REAL, error REAL,
              accepted INTEGER NOT NULL, rejected INTEGER NOT NULL, best REAL,
              PRIMARY KEY(resolution, miner, ts)) WITHOUT ROWID
            """)
        migrate(migrations)
    }

    /// A file that is no database or lost pages stays broken, and every write would fail silently. It moves aside,
    /// so it can still be rescued, and recording goes on in a new file.
    private func recover() {
        guard !isRecovering, let path else { return }
        isRecovering = true
        defer { isRecovering = false }
        if let db { sqlite3_close(db) }
        db = nil
        let stamp = Date().formatted(.iso8601.year().month().day().dateSeparator(.omitted).time(includingFractionalSeconds: false).timeSeparator(.omitted))
        let backup = "\(path).defekt-\(stamp)"
        try? FileManager.default.moveItem(atPath: path, toPath: backup)
        for suffix in ["-wal", "-shm", "-journal"] {
            try? FileManager.default.moveItem(atPath: path + suffix, toPath: backup + suffix)
        }
        damagedBackup = backup
        Log.app.error("History database damaged, created anew")
        buckets = [:]
        open()
        onDamaged?()
    }

    private func recoverIfDamaged(_ code: Int32) {
        // SQLITE_CORRUPT and SQLITE_NOTADB, also as extended codes.
        if code & 0xFF == SQLITE_CORRUPT || code & 0xFF == SQLITE_NOTADB { recover() }
    }

    /// Schema changes, in order. Never edit one that shipped; add a new one. `PRAGMA user_version` counts those done.
    static let migrations: [String] = []

    private func migrate(_ steps: [String]) {
        var version = 0
        run("PRAGMA user_version", bind: { _ in }, row: { version = Int(sqlite3_column_int($0, 0)) })
        for (index, step) in steps.enumerated() where index >= version {
            exec("BEGIN")
            guard exec(step), exec("PRAGMA user_version = \(index + 1)") else {
                exec("ROLLBACK")
                return
            }
            exec("COMMIT")
        }
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    static var defaultPath: String {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = Bundle.main.bundleIdentifier ?? "MinerGuru"
        return support.appendingPathComponent(folder).appendingPathComponent("history.sqlite").path
    }

    // MARK: - Writing

    /// Adds the readings of one poll. A finished minute goes to disk.
    func record(_ readings: [Reading]) {
        queue.async { [self] in
            for reading in readings { add(reading) }
            if let now = readings.first?.date, lastRollup.map({ now.timeIntervalSince($0) >= 600 }) ?? true {
                lastRollup = now
                rollUp(now: now)
            }
        }
    }

    /// Writes the running minutes and rollups, so a query sees everything up to now.
    func flush(now: Date = Date()) {
        queue.sync {
            writeBuckets(now: now)
            rollUp(now: now)
        }
    }

    func forget(minerID: UUID) {
        queue.async { [self] in
            buckets[minerID] = nil
            lastCounters[minerID] = nil
            run("DELETE FROM samples WHERE miner = ?") { sqlite3_bind_text($0, 1, minerID.uuidString, -1, Self.transient) }
        }
    }

    /// Saves the running minutes; a minute that is over is done with.
    private func writeBuckets(now: Date) {
        let minute = Int(now.timeIntervalSince1970) / 60
        for (id, bucket) in buckets { write(id, bucket) }
        buckets = buckets.filter { $0.value.minute >= minute }
    }

    private func add(_ r: Reading) {
        let minute = Int(r.date.timeIntervalSince1970) / 60
        var bucket = buckets[r.minerID] ?? Bucket(minute: minute)
        if bucket.minute != minute {
            write(r.minerID, bucket)
            bucket = Bucket(minute: minute)
        }
        bucket.polls += 1
        if r.isOnline {
            bucket.onlinePolls += 1
            bucket.hashRate += r.hashRateGHs
            bucket.temp += r.asicTempC
            bucket.maxTemp = max(bucket.maxTemp, r.asicTempC)
            if let vr = r.vrTempC, vr > 0 { bucket.vr += vr; bucket.vrCount += 1 }
            bucket.power += r.powerWatts
            bucket.fan += r.fanPercent
            if let latency = r.poolLatencyMs, latency > 0 { bucket.latency += latency; bucket.latencyCount += 1 }
            if let error = r.errorPercent { bucket.error += error; bucket.errorCount += 1 }
            bucket.best = max(bucket.best, r.bestDiff)
            // Counters restart with the miner; what it counted since then is new.
            if let last = lastCounters[r.minerID] {
                bucket.accepted += r.sharesAccepted >= last.accepted ? r.sharesAccepted - last.accepted : r.sharesAccepted
                bucket.rejected += r.sharesRejected >= last.rejected ? r.sharesRejected - last.rejected : r.sharesRejected
            }
            lastCounters[r.minerID] = (r.sharesAccepted, r.sharesRejected)
        }
        buckets[r.minerID] = bucket
    }

    private func write(_ id: UUID, _ b: Bucket) {
        guard b.polls > 0 else { return }
        let online = b.onlinePolls > 0
        func average(_ sum: Double, _ count: Int) -> Double? { count > 0 ? sum / Double(count) : nil }
        run("""
            INSERT OR REPLACE INTO samples VALUES(60, ?1, ?2, ?3, 1, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)
            """) { s in
            sqlite3_bind_text(s, 1, id.uuidString, -1, Self.transient)
            sqlite3_bind_int64(s, 2, Int64(b.minute) * 60)
            sqlite3_bind_int(s, 3, online ? 1 : 0)
            Self.bind(s, 4, average(b.hashRate, b.onlinePolls))
            Self.bind(s, 5, average(b.temp, b.onlinePolls))
            Self.bind(s, 6, online ? b.maxTemp : nil)
            Self.bind(s, 7, average(b.vr, b.vrCount))
            Self.bind(s, 8, average(b.power, b.onlinePolls))
            Self.bind(s, 9, average(b.fan, b.onlinePolls))
            Self.bind(s, 10, average(b.latency, b.latencyCount))
            Self.bind(s, 11, average(b.error, b.errorCount))
            sqlite3_bind_int64(s, 12, Int64(b.accepted))
            sqlite3_bind_int64(s, 13, Int64(b.rejected))
            Self.bind(s, 14, online && b.best > 0 ? b.best : nil)
        }
    }

    /// Averages are weighted by online minutes, so a half hour online does not count like a whole one.
    private func rollUp(now: Date) {
        // The first round after a start also covers what the last run left unfinished.
        let window = hasRolledUp ? 3 * 3600 : Self.minuteRetention
        hasRolledUp = true
        let since = Int64(now.timeIntervalSince1970 - window)
        run("""
            INSERT OR REPLACE INTO samples
            SELECT 3600, miner, ts / 3600 * 3600, SUM(online), SUM(total),
              SUM(hashrate * online) / NULLIF(SUM(online), 0), SUM(asic * online) / NULLIF(SUM(online), 0), MAX(asic_max),
              AVG(vr), SUM(power * online) / NULLIF(SUM(online), 0), AVG(fan), AVG(latency), AVG(error),
              SUM(accepted), SUM(rejected), MAX(best)
            FROM samples WHERE resolution = 60 AND ts >= ?1 / 3600 * 3600 GROUP BY miner, ts / 3600
            """) { sqlite3_bind_int64($0, 1, since) }
        run("DELETE FROM samples WHERE resolution = 60 AND ts < ?1") {
            sqlite3_bind_int64($0, 1, Int64(now.timeIntervalSince1970 - Self.minuteRetention))
        }
        run("DELETE FROM samples WHERE resolution = 3600 AND ts < ?1") {
            sqlite3_bind_int64($0, 1, Int64(now.timeIntervalSince1970 - Self.hourRetention))
        }
    }

    // MARK: - Reading

    /// Points of one miner between two dates, at most `maxPoints`, oldest first.
    func points(minerID: UUID, from: Date, to: Date) async -> [HistoryPoint] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: query(minerID: minerID, from: from, to: to, step: Self.step(from: from, to: to)))
            }
        }
    }

    /// Hourly points of all miners, for reports and exports.
    func hourlyPoints(from: Date, to: Date) async -> [HistoryPoint] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let now = Date()
                writeBuckets(now: now)
                rollUp(now: now)
                continuation.resume(returning: query(minerID: nil, from: from, to: to, step: 3600))
            }
        }
    }

    /// Bucket size in seconds: at least a minute, an hour beyond the minute retention, and few enough for a chart.
    static func step(from: Date, to: Date) -> Int {
        step(span: to.timeIntervalSince(from))
    }

    /// Rounded to whole seconds, because a span of exactly 30 or 90 days sits on a bucket boundary:
    /// a fraction of a second more would otherwise pick the next larger bucket.
    static func step(span: TimeInterval) -> Int {
        let seconds = Int(span.rounded())
        let wanted = (seconds + maxPoints - 1) / maxPoints
        let base = seconds > 2 * 86_400 ? 3600 : 60
        return max(base, (wanted + base - 1) / base * base)
    }

    private func query(minerID: UUID?, from: Date, to: Date, step: Int) -> [HistoryPoint] {
        writeBuckets(now: Date())
        let resolution = step >= 3600 ? 3600 : 60
        var points: [HistoryPoint] = []
        run("""
            SELECT miner, ts / ?1 * ?1, SUM(online), SUM(total),
              SUM(hashrate * online) / NULLIF(SUM(online), 0), SUM(asic * online) / NULLIF(SUM(online), 0), MAX(asic_max),
              AVG(vr), SUM(power * online) / NULLIF(SUM(online), 0), AVG(fan), AVG(latency), AVG(error),
              SUM(accepted), SUM(rejected), MAX(best)
            FROM samples WHERE resolution = ?2 AND ts >= ?3 AND ts <= ?4 AND (?5 IS NULL OR miner = ?5)
            GROUP BY miner, ts / ?1 ORDER BY 2, 1
            """, bind: { s in
            sqlite3_bind_int64(s, 1, Int64(step))
            sqlite3_bind_int(s, 2, Int32(resolution))
            sqlite3_bind_int64(s, 3, Int64(from.timeIntervalSince1970))
            sqlite3_bind_int64(s, 4, Int64(to.timeIntervalSince1970))
            if let minerID {
                sqlite3_bind_text(s, 5, minerID.uuidString, -1, Self.transient)
            } else {
                sqlite3_bind_null(s, 5)
            }
        }, row: { s in
            points.append(HistoryPoint(
                minerID: UUID(uuidString: String(cString: sqlite3_column_text(s, 0))),
                date: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(s, 1))),
                onlineMinutes: Int(sqlite3_column_int64(s, 2)),
                recordedMinutes: Int(sqlite3_column_int64(s, 3)),
                hashRateGHs: Self.double(s, 4), asicTempC: Self.double(s, 5), maxAsicTempC: Self.double(s, 6),
                vrTempC: Self.double(s, 7), powerWatts: Self.double(s, 8), fanPercent: Self.double(s, 9),
                poolLatencyMs: Self.double(s, 10), errorPercent: Self.double(s, 11),
                sharesAccepted: Int(sqlite3_column_int64(s, 12)), sharesRejected: Int(sqlite3_column_int64(s, 13)),
                bestDiff: Self.double(s, 14)
            ))
        })
        return points
    }

    // MARK: - SQLite

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: Double?) {
        if let value { sqlite3_bind_double(statement, index, value) } else { sqlite3_bind_null(statement, index) }
    }

    private static func double(_ statement: OpaquePointer?, _ index: Int32) -> Double? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_double(statement, index)
    }

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        guard let db else { return false }
        let code = sqlite3_exec(db, sql, nil, nil, nil)
        guard code == SQLITE_OK else {
            Log.app.error("History: \(String(cString: sqlite3_errmsg(db)), privacy: .public)")
            recoverIfDamaged(code)
            return false
        }
        return true
    }

    private func run(_ sql: String, bind: (OpaquePointer?) -> Void, row: ((OpaquePointer?) -> Void)? = nil) {
        guard let db else { return }
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard prepared == SQLITE_OK else {
            Log.app.error("History: \(String(cString: sqlite3_errmsg(db)), privacy: .public)")
            recoverIfDamaged(prepared)
            return
        }
        bind(statement)
        var code = sqlite3_step(statement)
        while code == SQLITE_ROW {
            row?(statement)
            code = sqlite3_step(statement)
        }
        // Finalized first: recovering closes the connection.
        sqlite3_finalize(statement)
        if code != SQLITE_DONE { recoverIfDamaged(code) }
    }
}
