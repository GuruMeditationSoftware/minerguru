import Foundation

/// Watches one miner for overheating, flatline (ESP-Miner #1053: the miner answers and draws power,
/// but no shares arrive and its averages freeze), a fallback pool it does not leave (#1618) and
/// restarts nobody asked for. All but the restart need more than one poll, to avoid false alarms.
struct MinerHealth: Equatable, Sendable {
    enum AutoRestartReason: Sendable {
        case flatline, stuckOnFallback
    }

    /// NerdOS has no overheat flag: warn this close to its limit …
    static let overheatMargin = 3.0
    /// … for this many polls in a row. As many polls below the limit end the alarm.
    static let overheatPolls = 3
    /// A flatline needs at least this long without a share, and ten expected share intervals.
    static let flatlineMinimum: TimeInterval = 10 * 60
    static let flatlineShareIntervals = 10.0
    /// `hashRate_1m` must also stand still this long and over this many polls.
    static let frozenDuration: TimeInterval = 5 * 60
    static let frozenPolls = 5
    /// Shares take a while after a restart.
    static let startupGrace = 5 * 60
    /// Uptime has to fall by more than this to count as a restart: answers can arrive out of order.
    static let uptimeTolerance = 60
    /// On the fallback pool this long in a row …
    static let fallbackAlarm: TimeInterval = 10 * 60
    /// … and with the primary pool answering this long, the miner should have switched back.
    static let stuckOnFallback: TimeInterval = 15 * 60
    /// The watchdog restarts a miner at most this often, then only alarms remain.
    static let autoRestartInterval: TimeInterval = 60 * 60
    /// How often the diagnostic log gets the measurements.
    static let snapshotInterval: TimeInterval = 15 * 60

    private var shares: Int?
    private var sharesChangedAt: Date?
    private var hashRate: Double?
    private var hashRateChangedAt: Date?
    private var samePolls = 0
    private var hotPolls = 0
    private var coolPolls = 0
    private var lastSnapshotAt: Date?
    private var peakStall: TimeInterval = 0
    private var fallbackSince: Date?
    private var primaryUpSince: Date?
    private var lastUptime: Int?

    private(set) var isOverheating = false
    private(set) var isFlatlining = false
    private(set) var isOnFallback = false
    private(set) var isStuckOnFallback = false
    /// The last poll found a restart MinerGuru did not ask for.
    private(set) var restartedUnexpectedly = false

    var overheatAlerted = false
    var lastOverheatAlertAt: Date?
    var flatlineAlerted = false
    var lastFlatlineAlertAt: Date?
    var fallbackAlerted = false
    var lastFallbackAlertAt: Date?
    var stuckAlerted = false
    var lastProfile: String?

    /// Minutes without a new share, for the alarm text.
    func minutesWithoutShares(at now: Date) -> Int {
        Int(now.timeIntervalSince(sharesChangedAt ?? now) / 60)
    }

    mutating func update(_ info: MinerSystemInfo, primaryReachable: Bool = false, restartExpected: Bool = false, at now: Date) {
        updateOverheat(info)
        updateFlatline(info, at: now)
        updateFallback(info, primaryReachable: primaryReachable, at: now)
        restartedUnexpectedly = lastUptime.map { info.uptimeSeconds + Self.uptimeTolerance < $0 } == true && !restartExpected
        lastUptime = info.uptimeSeconds
    }

    private mutating func updateFallback(_ info: MinerSystemInfo, primaryReachable: Bool, at now: Date) {
        guard info.isUsingFallbackStratum, !info.isDualPoolMining else {
            fallbackSince = nil
            primaryUpSince = nil
            isOnFallback = false
            isStuckOnFallback = false
            return
        }
        // Right after a start any miner may try the fallback pool, and a paused one proves nothing.
        if info.uptimeSeconds < Self.startupGrace || info.miningPaused {
            fallbackSince = nil
            primaryUpSince = nil
            isStuckOnFallback = false
            return
        }
        let since = fallbackSince ?? now
        fallbackSince = since
        primaryUpSince = primaryReachable ? (primaryUpSince ?? now) : nil
        isOnFallback = isOnFallback || now.timeIntervalSince(since) >= Self.fallbackAlarm
        isStuckOnFallback = isOnFallback && primaryUpSince.map { now.timeIntervalSince($0) >= Self.stuckOnFallback } == true
    }

    /// What the watchdog should do now, if the user allowed it. Never with an overheated miner.
    func dueAutoRestart(onFlatline: Bool, toPrimary: Bool, lastRestart: Date?, at now: Date) -> AutoRestartReason? {
        if isOverheating { return nil }
        if let lastRestart, now.timeIntervalSince(lastRestart) < Self.autoRestartInterval { return nil }
        if onFlatline && isFlatlining { return .flatline }
        if toPrimary && isStuckOnFallback { return .stuckOnFallback }
        return nil
    }

    private mutating func updateOverheat(_ info: MinerSystemInfo) {
        var hot = info.overheatMode
        if let limit = info.overheatTemp, limit > 0 {
            hot = hot || info.temp >= limit - Self.overheatMargin || (info.vrTemp ?? 0) > limit
        }
        hotPolls = hot ? hotPolls + 1 : 0
        coolPolls = hot ? 0 : coolPolls + 1
        if info.overheatMode || hotPolls >= Self.overheatPolls {
            isOverheating = true
        } else if coolPolls >= Self.overheatPolls {
            isOverheating = false
        }
    }

    private mutating func updateFlatline(_ info: MinerSystemInfo, at now: Date) {
        let rate = info.hashRate1m ?? 0
        if rate != hashRate {
            hashRate = rate
            hashRateChangedAt = now
            samePolls = 0
        } else {
            samePolls += 1
        }
        peakStall = max(peakStall, now.timeIntervalSince(sharesChangedAt ?? now))
        let restarting = info.uptimeSeconds < Self.startupGrace
        if info.sharesAccepted != shares || restarting || info.miningPaused || rate <= 0 {
            shares = info.sharesAccepted
            sharesChangedAt = now
            isFlatlining = false
            return
        }
        let stalled = now.timeIntervalSince(sharesChangedAt ?? now) >= Self.flatlineWindow(hashRateGHs: rate, poolDifficulty: info.activePoolDifficulty)
        let frozen = samePolls >= Self.frozenPolls && now.timeIntervalSince(hashRateChangedAt ?? now) >= Self.frozenDuration
        isFlatlining = stalled && frozen
    }

    /// The measurements behind both alarms, once every `snapshotInterval`: what thresholds are judged by.
    mutating func snapshot(_ info: MinerSystemInfo, at now: Date) -> String? {
        if let lastSnapshotAt, now.timeIntervalSince(lastSnapshotAt) < Self.snapshotInterval { return nil }
        lastSnapshotAt = now
        let rate = info.hashRate1m ?? 0
        let window = Self.flatlineWindow(hashRateGHs: rate, poolDifficulty: info.activePoolDifficulty)
        defer { peakStall = 0 }
        return [
            "temp=\(info.temp)", "vr=\(info.vrTemp.map { "\($0)" } ?? "-")", "limit=\(info.overheatTemp.map { "\($0)" } ?? "-")",
            "flag=\(info.overheatMode ? 1 : 0)", "paused=\(info.miningPaused ? 1 : 0)", "rate1m=\(rate)",
            "shares=\(info.sharesAccepted)", "uptime=\(info.uptimeSeconds)", "diff=\(info.activePoolDifficulty.map { "\($0)" } ?? "-")",
            "stallMin=\(minutesWithoutShares(at: now))", "peakStallMin=\(Int(peakStall / 60))", "windowMin=\(Int(window / 60))",
            "frozenPolls=\(samePolls)", "hotPolls=\(hotPolls)",
        ].joined(separator: " ")
    }

    /// How long a healthy miner can go without a share: `difficulty × 2³² / hashrate` per share on average.
    static func flatlineWindow(hashRateGHs: Double, poolDifficulty: Double?) -> TimeInterval {
        guard let poolDifficulty, poolDifficulty > 0, hashRateGHs > 0 else { return flatlineMinimum }
        let interval = poolDifficulty * 4_294_967_296 / (hashRateGHs * 1e9)
        return max(flatlineMinimum, flatlineShareIntervals * interval)
    }
}
