import Testing
import Foundation
import Network
import SQLite3
@testable import MinerGuru

private func reading(_ id: UUID, _ date: Date, online: Bool = true, hash: Double = 500, power: Double = 15, accepted: Int = 0, rejected: Int = 0) -> HistoryStore.Reading {
    HistoryStore.Reading(minerID: id, date: date, isOnline: online, hashRateGHs: hash, asicTempC: 55, powerWatts: power,
                         fanPercent: 40, errorPercent: 0.1, sharesAccepted: accepted, sharesRejected: rejected, bestDiff: 1000)
}

private let berlin: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return calendar
}()

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    berlin.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

@Suite("Verlauf: Schema")
struct HistoryMigrationTests {
    @Test func stepsRunOnceAndAStoreOpensAgain() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("history.sqlite").path
        let steps = ["ALTER TABLE samples ADD COLUMN extra REAL"]
        _ = HistoryStore(path: path)
        // A second run of the step would fail on the existing column and leave user_version behind.
        _ = HistoryStore(path: path, migrations: steps)
        _ = HistoryStore(path: path, migrations: steps + ["ALTER TABLE samples ADD COLUMN more REAL"])

        var db: OpaquePointer?
        #expect(sqlite3_open(path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        sqlite3_step(statement)
        #expect(sqlite3_column_int(statement, 0) == 2)
    }
}

@Suite("Verlauf: beschädigte Datei")
struct HistoryDamageTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func aDamagedFileMovesAsideAtStart() async throws {
        let dir = try folder()
        let file = dir.appendingPathComponent("history.sqlite")
        try Data(repeating: 0x5A, count: 8192).write(to: file)

        let store = HistoryStore(path: file.path)

        let backup = try #require(store.damagedBackup)
        #expect(FileManager.default.contents(atPath: backup)?.count == 8192)
        let id = UUID(), now = Date(timeIntervalSince1970: 1_800_000_000)
        store.record([reading(id, now)])
        store.flush(now: now.addingTimeInterval(120))
        #expect(await store.points(minerID: id, from: now.addingTimeInterval(-3600), to: now.addingTimeInterval(3600)).count == 1)
    }

    @Test func aFileDamagedBetweenStartsMovesAside() async throws {
        let dir = try folder()
        let file = dir.appendingPathComponent("history.sqlite")
        let store = HistoryStore(path: file.path)
        let id = UUID(), now = Date(timeIntervalSince1970: 1_800_000_000)
        store.record([reading(id, now)])
        store.flush(now: now.addingTimeInterval(120))
        _ = await store.points(minerID: id, from: now, to: now)
        let handle = try FileHandle(forWritingTo: file)
        try handle.write(contentsOf: Data(repeating: 0x5A, count: 8192))
        try handle.close()
        try? FileManager.default.removeItem(atPath: file.path + "-wal")
        try? FileManager.default.removeItem(atPath: file.path + "-shm")

        let reopened = HistoryStore(path: file.path)
        _ = await reopened.points(minerID: id, from: now, to: now)
        #expect(reopened.damagedBackup != nil)
    }

    @Test func aHealthyFileStaysInPlace() async throws {
        let file = try folder().appendingPathComponent("history.sqlite")
        let first = HistoryStore(path: file.path)
        let id = UUID(), now = Date(timeIntervalSince1970: 1_800_000_000)
        first.record([reading(id, now)])
        first.flush(now: now.addingTimeInterval(120))
        _ = await first.points(minerID: id, from: now, to: now)
        #expect(HistoryStore(path: file.path).damagedBackup == nil)
    }
}

@Suite("Langzeit-Verlauf")
struct HistoryStoreTests {
    @Test func averagesPollsPerMinuteAndCountsOffline() async {
        let store = HistoryStore(path: nil)
        let id = UUID()
        let start = Date(timeIntervalSince1970: 1_800_000_000 / 60 * 60)
        store.record([reading(id, start, hash: 400)])
        store.record([reading(id, start.addingTimeInterval(10), hash: 600)])
        store.record([reading(id, start.addingTimeInterval(60), online: false)])
        store.record([reading(id, start.addingTimeInterval(120), hash: 500)])
        store.flush(now: start.addingTimeInterval(180))

        let points = await store.points(minerID: id, from: start, to: start.addingTimeInterval(300))
        #expect(points.count == 3)
        #expect(points[0].hashRateGHs == 500)
        #expect(points[1].onlineMinutes == 0)
        #expect(points[1].recordedMinutes == 1)
        #expect(points[1].hashRateGHs == nil)
    }

    @Test func shareCountersSurviveARestart() async {
        let store = HistoryStore(path: nil)
        let id = UUID()
        let start = Date(timeIntervalSince1970: 1_800_000_000 / 60 * 60)
        store.record([reading(id, start, accepted: 100)])
        store.record([reading(id, start.addingTimeInterval(60), accepted: 130)])
        store.record([reading(id, start.addingTimeInterval(120), accepted: 5)])
        store.flush(now: start.addingTimeInterval(180))

        let points = await store.hourlyPoints(from: start.addingTimeInterval(-3600), to: start.addingTimeInterval(3600))
        #expect(points.reduce(0) { $0 + $1.sharesAccepted } == 35)
    }

    @Test func hourlyRollupWeighsByOnlineMinutesAndIsRepeatable() async {
        let store = HistoryStore(path: nil)
        let id = UUID()
        let hour = Date(timeIntervalSince1970: 1_800_000_000 / 3600 * 3600)
        for minute in 0..<30 {
            store.record([reading(id, hour.addingTimeInterval(Double(minute) * 60), hash: 600)])
        }
        for minute in 30..<60 {
            store.record([reading(id, hour.addingTimeInterval(Double(minute) * 60), online: false)])
        }
        store.flush(now: hour.addingTimeInterval(3600))
        store.flush(now: hour.addingTimeInterval(3660))

        let points = await store.hourlyPoints(from: hour, to: hour.addingTimeInterval(1800))
        #expect(points.count == 1)
        #expect(points[0].hashRateGHs == 600)
        #expect(points[0].onlineMinutes == 30)
        #expect(points[0].recordedMinutes == 60)
    }

    @Test func oldMinuteRowsGoAwayButHoursStay() async {
        let store = HistoryStore(path: nil)
        let id = UUID()
        let old = Date(timeIntervalSince1970: 1_800_000_000 / 3600 * 3600)
        store.record([reading(id, old)])
        store.flush(now: old.addingTimeInterval(60))
        store.flush(now: old.addingTimeInterval(HistoryStore.minuteRetention + 86_400))

        let hours = await store.hourlyPoints(from: old.addingTimeInterval(-60), to: old.addingTimeInterval(60))
        #expect(hours.count == 1)
        let minutes = await store.points(minerID: id, from: old.addingTimeInterval(-60), to: old.addingTimeInterval(60))
        #expect(minutes.isEmpty)
    }

    @Test func stepKeepsChartsSmall() {
        let now = Date()
        #expect(HistoryStore.step(from: now.addingTimeInterval(-86_400), to: now) == 120)
        #expect(HistoryStore.step(from: now.addingTimeInterval(-7 * 86_400), to: now) == 3600)
        #expect(HistoryStore.step(from: now.addingTimeInterval(-365 * 86_400), to: now) >= 3600 * 12)
    }

    @Test func stepOfARangeIgnoresFractionsOfASecond() {
        for range in HistoryRange.allCases {
            let exact = HistoryStore.step(span: range.seconds)
            #expect(HistoryStore.step(span: range.seconds + 0.000_001) == exact)
            #expect(HistoryStore.step(span: range.seconds - 0.000_001) == exact)
        }
        #expect(HistoryStore.step(span: HistoryRange.month.seconds) == 3600)
        #expect(HistoryStore.step(span: HistoryRange.quarter.seconds) == 10_800)
    }

    @Test func segmentsSplitAtGapsBeyondThreeSteps() {
        func point(hour: Double, hashrate: Double? = 1000) -> HistoryPoint {
            HistoryPoint(minerID: nil, date: Date(timeIntervalSince1970: hour * 3600), onlineMinutes: 1, recordedMinutes: 1,
                         hashRateGHs: hashrate, powerWatts: 15, sharesAccepted: 0, sharesRejected: 0)
        }
        let points = [point(hour: 0), point(hour: 3), point(hour: 14), point(hour: 15, hashrate: nil), point(hour: 17)]
        let segments = HistoryMetric.hashrate.segments(of: points, in: .quarter)
        #expect(segments.map(\.count) == [2, 2])
    }

    @Test func csvHasOneLinePerPoint() {
        let point = HistoryPoint(minerID: nil, date: Date(timeIntervalSince1970: 0), onlineMinutes: 1, recordedMinutes: 1,
                                 hashRateGHs: 1000, powerWatts: 15, sharesAccepted: 1, sharesRejected: 0)
        let csv = HistoryCSV.text(points: [point], minerName: { _ in "a\"b" })
        #expect(csv.contains("\"a\"\"b\""))
        #expect(csv.contains("15.000"))
        #expect(csv.split(separator: "\n").count == 2)
    }
}

@Suite("Pool-Zeitplan")
struct PoolScheduleTests {
    private func rule(_ days: Set<Weekday>, minute: Int) -> PoolScheduleRule {
        PoolScheduleRule(poolID: UUID(), weekdays: days, minute: minute, createdAt: date(2026, 1, 1))
    }

    @Test func findsTheLastOccurrence() {
        // 2026-11-06 is a Friday.
        let r = rule([6], minute: 22 * 60)
        #expect(r.lastOccurrence(before: date(2026, 11, 6, 23), calendar: berlin) == date(2026, 11, 6, 22))
        #expect(r.lastOccurrence(before: date(2026, 11, 6, 21), calendar: berlin) == date(2026, 10, 30, 22))
    }

    @Test func runsOnceAndCatchesUpForHalfAnHour() {
        let r = rule([6], minute: 22 * 60)
        let moment = date(2026, 11, 6, 22)
        #expect(r.dueOccurrence(at: date(2026, 11, 6, 22, 1), lastApplied: nil, calendar: berlin) == moment)
        #expect(r.dueOccurrence(at: date(2026, 11, 6, 22, 1), lastApplied: moment, calendar: berlin) == nil)
        #expect(r.dueOccurrence(at: date(2026, 11, 6, 22, 29), lastApplied: nil, calendar: berlin) == moment)
        #expect(r.dueOccurrence(at: date(2026, 11, 6, 22, 31), lastApplied: nil, calendar: berlin) == nil)
    }

    @Test func aNewRuleDoesNotFireForThePast() {
        var r = rule([6], minute: 22 * 60)
        r.createdAt = date(2026, 11, 6, 22, 5)
        #expect(r.dueOccurrence(at: date(2026, 11, 6, 22, 10), lastApplied: nil, calendar: berlin) == nil)
    }

    @Test func disabledRulesStayQuiet() {
        var r = rule([6], minute: 22 * 60)
        r.isEnabled = false
        #expect(r.dueOccurrence(at: date(2026, 11, 6, 22, 1), lastApplied: nil, calendar: berlin) == nil)
    }
}

@Suite("Wartung")
@MainActor
struct MaintenanceTests {
    private func defaults() -> UserDefaults {
        let name = "maintenance-\(UUID())"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func status() {
        let now = date(2026, 11, 4, 12)
        var task = MaintenanceTask(kind: .fanCleaning, intervalDays: 90, nextDue: date(2026, 11, 3))
        #expect(task.status(at: now, calendar: berlin) == .overdue)
        task.nextDue = date(2026, 11, 10)
        #expect(task.status(at: now, calendar: berlin) == .dueSoon)
        task.nextDue = date(2026, 12, 10)
        #expect(task.status(at: now, calendar: berlin) == .planned)
    }

    @Test func doneMovesTheNextDateAndKeepsARecord() {
        let store = MaintenanceStore(defaults: defaults())
        let task = MaintenanceTask(kind: .fanCleaning, intervalDays: 90, nextDue: date(2026, 11, 1))
        store.upsert(task)
        store.markDone(task, on: date(2026, 11, 4))
        #expect(store.tasks[0].nextDue == Calendar.current.date(byAdding: .day, value: 90, to: date(2026, 11, 4)))
        #expect(store.records.count == 1)
    }

    @Test func aOneTimeTaskDisappears() {
        let store = MaintenanceStore(defaults: defaults())
        let task = MaintenanceTask(kind: .custom, customTitle: "Regal", intervalDays: 0, nextDue: date(2026, 11, 1))
        store.upsert(task)
        store.markDone(task)
        #expect(store.tasks.isEmpty)
        #expect(store.records[0].title == "Regal")
    }

    @Test func remindsOncePerDay() {
        let store = MaintenanceStore(defaults: defaults())
        let now = date(2026, 11, 4, 12)
        store.upsert(MaintenanceTask(kind: .firmware, intervalDays: 30, nextDue: date(2026, 11, 1)))
        #expect(store.dueEvents(at: now).count == 1)
        #expect(store.dueEvents(at: now.addingTimeInterval(3600)).isEmpty)
        #expect(store.dueEvents(at: now.addingTimeInterval(86_400)).count == 1)
    }

    @Test func survivesARestart() {
        let d = defaults()
        MaintenanceStore(defaults: d).upsert(MaintenanceTask(kind: .dust, intervalDays: 180, nextDue: date(2026, 12, 1)))
        #expect(MaintenanceStore(defaults: d).tasks.count == 1)
    }
}

@Suite("Berichte")
struct MinerReportTests {
    @Test func buildsFiguresFromHourlyRows() {
        let id = UUID()
        let start = date(2026, 11, 3)
        let interval = DateInterval(start: start, duration: 2 * 3600)
        let points = [
            HistoryPoint(minerID: id, date: start, onlineMinutes: 60, recordedMinutes: 60, hashRateGHs: 1000, asicTempC: 50,
                         maxAsicTempC: 60, powerWatts: 20, sharesAccepted: 10, sharesRejected: 1, bestDiff: 100),
            HistoryPoint(minerID: id, date: start.addingTimeInterval(3600), onlineMinutes: 30, recordedMinutes: 60, hashRateGHs: 400,
                         asicTempC: 56, maxAsicTempC: 70, powerWatts: 10, sharesAccepted: 5, sharesRejected: 0, bestDiff: 300),
        ]
        let record = MaintenanceRecord(kind: .firmware, title: "Update", minerIDs: [], doneAt: start.addingTimeInterval(60))
        let outside = MaintenanceRecord(kind: .firmware, title: "Alt", minerIDs: [], doneAt: start.addingTimeInterval(-60))
        let report = MinerReport.build(interval: interval, points: points, minerName: { _ in "Test" }, price: { _ in 0.5 },
                                       maintenance: [record, outside], calendar: berlin)
        let row = report.rows[0]
        #expect(row.uptimePercent == 75)
        #expect(row.averageHashRateGHs == 800)
        #expect(abs(row.energyKWh - 0.025) < 1e-9)
        #expect(abs(row.cost - 0.0125) < 1e-9)
        #expect(row.maxTempC == 70)
        #expect(row.sharesAccepted == 15)
        #expect(report.bestDiff == 300)
        #expect(report.maintenance.map(\.title) == ["Update"])
        #expect(report.csvText().contains("\"Test\",75.00,800.00,0.025"))
    }

    @Test func periods() {
        let now = date(2026, 11, 4, 12)
        #expect(ReportPeriod.lastMonth.interval(now: now, calendar: berlin) == DateInterval(start: date(2026, 10, 1), end: date(2026, 11, 1)))
        #expect(ReportPeriod.yesterday.interval(now: now, calendar: berlin) == DateInterval(start: date(2026, 11, 3), end: date(2026, 11, 4)))
    }
}

@Suite("SMTP")
struct SmtpTests {
    @Test func sendsThroughARealSocket() async throws {
        let server = try FakeSmtpServer()
        let host = SmtpServer(host: "127.0.0.1", port: server.port, security: .none, username: "u", password: "p")
        try await SmtpClient.send(message, via: host, timeout: 5)
        let received = await server.received()
        #expect(received.contains("AUTH LOGIN"))
        #expect(received.contains("RCPT TO:<c@example.com>"))
        #expect(received.contains("Content-Transfer-Encoding: base64"))
    }

    @Test func reportsAServerThatIsNotThere() async {
        let host = SmtpServer(host: "127.0.0.1", port: 1, security: .none, username: "", password: "")
        await #expect(throws: (any Error).self) { try await SmtpClient.send(message, via: host, timeout: 2) }
    }

    private let message = SmtpMessage(from: "a@example.com", to: ["b@example.com", "c@example.com"], subject: "Prüfung", body: "Hallo")

    @Test func fullDialogueWithStartTLSAndLogin() throws {
        var d = SmtpDialogue(message: message, username: "u", password: "p", useStartTLS: true, clientName: "x")
        #expect(try d.next(code: 220, text: "220 hi") == .send("EHLO x"))
        #expect(try d.next(code: 250, text: "250-x\n250 STARTTLS") == .send("STARTTLS"))
        #expect(try d.next(code: 220, text: "220 go") == .startTLS)
        #expect(try d.next(code: 250, text: "250 AUTH LOGIN") == .send("AUTH LOGIN"))
        #expect(try d.next(code: 334, text: "334 VXNlcm5hbWU6") == .send("dQ=="))
        #expect(try d.next(code: 334, text: "334 UGFzc3dvcmQ6") == .send("cA=="))
        #expect(try d.next(code: 235, text: "235 ok") == .send("MAIL FROM:<a@example.com>"))
        #expect(try d.next(code: 250, text: "250 ok") == .send("RCPT TO:<b@example.com>"))
        #expect(try d.next(code: 250, text: "250 ok") == .send("RCPT TO:<c@example.com>"))
        #expect(try d.next(code: 250, text: "250 ok") == .send("DATA"))
        guard case .send(let data) = try d.next(code: 354, text: "354 go") else { Issue.record("no data"); return }
        #expect(data.hasSuffix("\r\n."))
        #expect(data.contains("Subject: =?UTF-8?B?"))
        #expect(try d.next(code: 250, text: "250 queued") == .send("QUIT"))
        #expect(try d.next(code: 221, text: "221 bye") == .done)
    }

    @Test func noLoginWithoutUser() throws {
        var d = SmtpDialogue(message: message, username: "", password: "", useStartTLS: false, clientName: "x")
        _ = try d.next(code: 220, text: "220 hi")
        #expect(try d.next(code: 250, text: "250 ok") == .send("MAIL FROM:<a@example.com>"))
    }

    @Test func refusesToGoOnWithoutStartTLS() throws {
        var d = SmtpDialogue(message: message, username: "u", password: "p", useStartTLS: true, clientName: "x")
        _ = try d.next(code: 220, text: "220 hi")
        #expect(throws: SmtpError.self) { try d.next(code: 250, text: "250 PIPELINING") }
    }

    @Test func wrongPasswordIsAnError() throws {
        var d = SmtpDialogue(message: message, username: "u", password: "p", useStartTLS: false, clientName: "x")
        _ = try d.next(code: 220, text: "220 hi")
        _ = try d.next(code: 250, text: "250 ok")
        _ = try d.next(code: 334, text: "334 a")
        _ = try d.next(code: 334, text: "334 b")
        #expect(throws: SmtpError.self) { try d.next(code: 535, text: "535 nope") }
    }

    @Test func dotsAreStuffed() {
        #expect(SmtpDialogue.dotStuffed("a\r\n.b\r\n..") == "a\r\n..b\r\n...")
    }
}

/// Answers one SMTP conversation on a local port.
private final class FakeSmtpServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "fake-smtp")
    private var text = ""
    private var inData = false
    private var finished: CheckedContinuation<String, Never>?
    private var isDone = false
    private(set) var port = 0

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        listener.newConnectionHandler = { [unowned self] connection in
            connection.start(queue: queue)
            send("220 fake\r\n", connection)
            receive(connection)
        }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 2)
        port = Int(listener.port?.rawValue ?? 0)
    }

    func received() async -> String {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                if isDone { continuation.resume(returning: text) } else { finished = continuation }
            }
        }
    }

    private func send(_ line: String, _ connection: NWConnection) {
        connection.send(content: Data(line.utf8), completion: .contentProcessed { _ in })
    }

    private func receive(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [self] data, _, _, error in
            guard let data, error == nil else { return }
            let chunk = String(decoding: data, as: UTF8.self)
            text += chunk
            if inData {
                if chunk.hasSuffix("\r\n.\r\n") {
                    inData = false
                    send("250 queued\r\n", connection)
                }
            } else if chunk.hasPrefix("EHLO") {
                send("250-fake\r\n250 AUTH LOGIN\r\n", connection)
            } else if chunk.hasPrefix("AUTH") {
                send("334 VXNlcm5hbWU6\r\n", connection)
            } else if chunk.hasPrefix("dQ==") {
                send("334 UGFzc3dvcmQ6\r\n", connection)
            } else if chunk.hasPrefix("cA==") {
                send("235 ok\r\n", connection)
            } else if chunk.hasPrefix("DATA") {
                inData = true
                send("354 go\r\n", connection)
            } else if chunk.hasPrefix("QUIT") {
                send("221 bye\r\n", connection)
                isDone = true
                finished?.resume(returning: text)
                finished = nil
                return
            } else {
                send("250 ok\r\n", connection)
            }
            receive(connection)
        }
    }
}
