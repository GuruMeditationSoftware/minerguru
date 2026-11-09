import Foundation
import Combine
import UserNotifications

/// Kinds of alerts the user can switch on or off. Later watchdogs add cases here.
enum AlertKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case offline
    case maintenance
    case overheat
    case flatline
    case fallback
    case restart
    case payout

    var id: String { rawValue }

    var title: String {
        switch self {
        case .offline: String(localized: "Miner offline / back online")
        case .maintenance: String(localized: "Maintenance due")
        case .overheat: String(localized: "Overheating")
        case .flatline: String(localized: "No more shares (flatline)")
        case .fallback: String(localized: "Fallback pool active")
        case .restart: String(localized: "Unexpected restart")
        case .payout: String(localized: "Payout address")
        }
    }
}

/// One message for the user. Only alarms, never news or advertising.
struct AlertEvent: Equatable, Sendable {
    let kind: AlertKind
    let minerID: UUID
    let title: String
    let body: String
    /// `true` for the all-clear after an alarm.
    let isRecovery: Bool
    /// Who it is about, for a message that names several.
    var minerName = ""
    /// Says what happened to one miner, so it is never folded into a message about several.
    var standsAlone = false

    /// One message per kind and direction for the alerts of one poll, so a power cut does not send one mail
    /// per miner. A combined message has no single miner: its `minerID` is empty.
    static func combine(_ events: [AlertEvent]) -> [AlertEvent] {
        var groups: [[AlertEvent]] = []
        for event in events where !event.standsAlone {
            if let index = groups.firstIndex(where: { $0[0].kind == event.kind && $0[0].isRecovery == event.isRecovery }) {
                groups[index].append(event)
            } else {
                groups.append([event])
            }
        }
        let combined = groups.map { group -> AlertEvent in
            guard group.count > 1 else { return group[0] }
            return AlertEvent(
                kind: group[0].kind, minerID: noMiner,
                title: combinedTitle(group[0].kind, recovery: group[0].isRecovery, count: group.count),
                body: group.reduce(into: [String]()) { names, event in
                    if !names.contains(event.minerName) { names.append(event.minerName) }
                }.joined(separator: ", "),
                isRecovery: group[0].isRecovery
            )
        }
        return combined + events.filter(\.standsAlone)
    }

    private static let noMiner = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    private static func combinedTitle(_ kind: AlertKind, recovery: Bool, count: Int) -> String {
        switch (kind, recovery) {
        case (.maintenance, _): String(localized: "\(count) maintenance tasks are due")
        case (.overheat, false): String(localized: "\(count) miners are overheating")
        case (.overheat, true): String(localized: "\(count) miners have cooled down")
        case (.flatline, false): String(localized: "\(count) miners have stopped delivering shares")
        case (.flatline, true): String(localized: "\(count) miners are delivering shares again")
        case (.fallback, false): String(localized: "\(count) miners are on the fallback pool")
        case (.fallback, true): String(localized: "\(count) miners are back on the primary pool")
        case (.restart, _): String(localized: "\(count) miners restarted")
        case (.payout, _): String(localized: "\(count) payout address warnings")
        case (.offline, false): String(localized: "\(count) miners are offline")
        case (.offline, true): String(localized: "\(count) miners are back online")
        }
    }
}

/// Delivers alerts. The real one uses macOS notifications; tests use a fake.
protocol AlertNotifier: Sendable {
    func requestAuthorization() async -> Bool
    func deliver(_ event: AlertEvent) async
}

/// macOS notification centre. Only works inside the app bundle, not in `swift test`.
struct UserNotificationNotifier: AlertNotifier {
    private var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            Log.app.error("Notifications not allowed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func deliver(_ event: AlertEvent) async {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.body
        content.sound = event.isRecovery ? nil : .default
        content.threadIdentifier = event.minerID.uuidString
        let request = UNNotificationRequest(
            identifier: "\(event.kind.rawValue)-\(event.minerID.uuidString)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            Log.app.error("Notification not delivered: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Turns poll results into alerts: debounced, per miner and per kind mutable.
@MainActor
final class AlertCenter: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            updateAppNapGuard()
            if isEnabled && !oldValue {
                Task { [notifier] in _ = await notifier.requestAuthorization() }
            }
        }
    }
    @Published private(set) var mutedMinerIDs: Set<UUID>
    /// All alerts stay quiet until then (set from Control Center: "until the morning").
    @Published private(set) var silencedUntil: Date? {
        didSet { defaults.set(silencedUntil?.timeIntervalSince1970, forKey: Self.silencedUntilKey) }
    }
    @Published private(set) var disabledKinds: Set<AlertKind>
    /// Off by default: restart a miner without shares, at most once an hour.
    @Published var restartsOnFlatline: Bool {
        didSet { defaults.set(restartsOnFlatline, forKey: Self.restartOnFlatlineKey) }
    }
    /// Off by default: restart a miner that stays on the fallback pool although the primary one answers.
    @Published var restartsToPrimary: Bool {
        didSet { defaults.set(restartsToPrimary, forKey: Self.restartToPrimaryKey) }
    }
    /// The address each coin should pay to, by `MinedCoin.rawValue`.
    @Published private(set) var expectedAddresses: [String: String]

    /// Set by `MinerStore`; replaced in tests.
    var restartMiner: @MainActor (MinerDevice) async throws -> Void = { try await MinerAPIClient.shared.restartMiner(host: $0.ipAddress) }
    /// Read-only mode, asked at the moment a restart falls due.
    var isReadOnly: @Sendable () -> Bool = { ChangeLog.isReadOnly }

    /// A miner counts as offline after this many failed polls in a row …
    static let offlineFailedPolls = 3
    /// … that also span at least this long (a manual restart takes 10–20 s).
    static let offlineMinimumDuration: TimeInterval = 90
    /// The same alarm for the same miner at most this often.
    static let repeatInterval: TimeInterval = 30 * 60
    /// A changed address this soon after a write from MinerGuru was the user's own change.
    static let ownChangeWindow: TimeInterval = 15 * 60
    /// Restarts this soon after one from MinerGuru are expected.
    static let ownRestartWindow: TimeInterval = 10 * 60
    /// The miner has to report a block without its address this many polls in a row.
    static let payoutMissPolls = 3

    private struct MinerTrack {
        var failedPolls = 0
        var firstFailureAt: Date?
        /// An offline alarm went out and the all-clear is still due.
        var offlineAlerted = false
        var lastOfflineAlertAt: Date?
        var health = MinerHealth()
        var wasOnline: Bool?
        var payoutMissPolls = 0
        var payoutMissAlerted = false
        /// A due restart was left out because of read-only mode; said once an hour at most.
        var lastSkippedRestartAt: Date?
    }

    private var tracks: [UUID: MinerTrack] = [:]
    private var payoutMemory: PayoutMemory
    private let defaults: UserDefaults
    private let notifier: AlertNotifier
    private let guardsAppNap: Bool
    private var appNapActivity: NSObjectProtocol?

    private static let enabledKey = "MinerGuru.AlertsEnabled.v1"
    private static let mutedKey = "MinerGuru.AlertsMutedMiners.v1"
    private static let silencedUntilKey = "MinerGuru.AlertsSilencedUntil.v1"
    /// Silencing lasts until this hour of the next morning.
    static let morningHour = 7
    private static let disabledKindsKey = "MinerGuru.AlertsDisabledKinds.v1"
    private static let restartOnFlatlineKey = "MinerGuru.RestartOnFlatline.v1"
    private static let restartToPrimaryKey = "MinerGuru.RestartToPrimary.v1"
    private static let expectedAddressesKey = "MinerGuru.PayoutExpected.v1"
    private static let payoutMemoryKey = "MinerGuru.PayoutMemory.v1"

    /// - Parameter guardsAppNap: Keeps macOS from throttling the polling timer while alerts are on
    ///   and no window is open. Off in tests.
    private let changeLog: ChangeLog

    init(defaults: UserDefaults, notifier: AlertNotifier = UserNotificationNotifier(), guardsAppNap: Bool = true, changeLog: ChangeLog = .shared) {
        self.changeLog = changeLog
        self.defaults = defaults
        self.notifier = notifier
        self.guardsAppNap = guardsAppNap
        self.isEnabled = defaults.bool(forKey: Self.enabledKey)
        let silenced = defaults.double(forKey: Self.silencedUntilKey)
        self.silencedUntil = silenced > 0 ? Date(timeIntervalSince1970: silenced) : nil
        self.mutedMinerIDs = Set((defaults.stringArray(forKey: Self.mutedKey) ?? []).compactMap(UUID.init(uuidString:)))
        self.disabledKinds = Set((defaults.stringArray(forKey: Self.disabledKindsKey) ?? []).compactMap(AlertKind.init(rawValue:)))
        self.restartsOnFlatline = defaults.bool(forKey: Self.restartOnFlatlineKey)
        self.restartsToPrimary = defaults.bool(forKey: Self.restartToPrimaryKey)
        self.expectedAddresses = (defaults.dictionary(forKey: Self.expectedAddressesKey) as? [String: String]) ?? [:]
        self.payoutMemory = defaults.data(forKey: Self.payoutMemoryKey)
            .flatMap { try? JSONDecoder().decode(PayoutMemory.self, from: $0) } ?? PayoutMemory()
        updateAppNapGuard()
    }

    // MARK: - Settings

    func isMuted(_ minerID: UUID) -> Bool { mutedMinerIDs.contains(minerID) }

    func isSilenced(at date: Date = Date()) -> Bool {
        silencedUntil.map { $0 > date } ?? false
    }

    /// Quiet until the next 7:00 (today's if it is still before 7, otherwise tomorrow's).
    func silenceUntilMorning(now: Date = Date(), calendar: Calendar = .current) {
        silencedUntil = Self.nextMorning(after: now, calendar: calendar)
    }

    func endSilence() {
        silencedUntil = nil
    }

    static func nextMorning(after date: Date, calendar: Calendar = .current) -> Date {
        calendar.nextDate(after: date, matching: DateComponents(hour: morningHour, minute: 0), matchingPolicy: .nextTime)
            ?? date.addingTimeInterval(12 * 3600)
    }

    func setMuted(_ muted: Bool, minerID: UUID) {
        if muted { mutedMinerIDs.insert(minerID) } else { mutedMinerIDs.remove(minerID) }
        defaults.set(mutedMinerIDs.map(\.uuidString).sorted(), forKey: Self.mutedKey)
    }

    func isKindEnabled(_ kind: AlertKind) -> Bool { !disabledKinds.contains(kind) }

    func setKind(_ kind: AlertKind, enabled: Bool) {
        if enabled { disabledKinds.remove(kind) } else { disabledKinds.insert(kind) }
        defaults.set(disabledKinds.map(\.rawValue).sorted(), forKey: Self.disabledKindsKey)
    }

    /// An empty address removes the coin. A new target makes earlier warnings worth repeating.
    func setExpectedAddress(_ address: String, for coin: MinedCoin) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        expectedAddresses[coin.rawValue] = trimmed.isEmpty ? nil : trimmed
        defaults.set(expectedAddresses, forKey: Self.expectedAddressesKey)
        payoutMemory.alerted = [:]
        savePayoutMemory()
    }

    private func savePayoutMemory() {
        if let data = try? JSONEncoder().encode(payoutMemory) {
            defaults.set(data, forKey: Self.payoutMemoryKey)
        }
    }

    func forget(minerID: UUID) {
        tracks[minerID] = nil
        payoutMemory.seen[minerID.uuidString] = nil
        payoutMemory.alerted[minerID.uuidString] = nil
        savePayoutMemory()
        if mutedMinerIDs.contains(minerID) { setMuted(false, minerID: minerID) }
    }

    // MARK: - Evaluation

    /// Call once per fleet poll. Returns the alerts that were sent (for tests).
    @discardableResult
    func evaluate(_ miners: [MinerDevice], now: Date = Date()) async -> [AlertEvent] {
        var events: [AlertEvent] = []
        var restarts: [(MinerDevice, MinerHealth.AutoRestartReason)] = []
        for miner in miners {
            var track = tracks[miner.id] ?? MinerTrack()
            logState(of: miner, &track, now: now)
            if case .offline = miner.connectionState {
                track.failedPolls += 1
                track.firstFailureAt = track.firstFailureAt ?? now
                let longEnough = now.timeIntervalSince(track.firstFailureAt ?? now) >= Self.offlineMinimumDuration
                let notRepeated = track.lastOfflineAlertAt.map { now.timeIntervalSince($0) >= Self.repeatInterval } ?? true
                if !track.offlineAlerted, track.failedPolls >= Self.offlineFailedPolls, longEnough, notRepeated {
                    track.offlineAlerted = true
                    track.lastOfflineAlertAt = now
                    events.append(AlertEvent(
                        kind: .offline,
                        minerID: miner.id,
                        title: String(localized: "\(miner.displayName) is offline"),
                        body: String(localized: "No response for \(Int(now.timeIntervalSince(track.firstFailureAt ?? now) / 60)) min. It may have lost power, be out of Wi-Fi range or be in hotspot mode."),
                        isRecovery: false
                    ))
                }
            } else if miner.connectionState.isOnline {
                if track.offlineAlerted {
                    events.append(AlertEvent(
                        kind: .offline,
                        minerID: miner.id,
                        title: String(localized: "\(miner.displayName) is back online"),
                        body: String(localized: "The miner is responding again."),
                        isRecovery: true
                    ))
                }
                track.failedPolls = 0
                track.firstFailureAt = nil
                track.offlineAlerted = false
                if let info = miner.latestInfo {
                    let restartExpected = changeLog.lastRestart(host: miner.ipAddress)
                        .map { now.timeIntervalSince($0) < Self.ownRestartWindow } ?? false
                    track.health.update(
                        info, primaryReachable: miner.poolLatency?.primaryPoolDirectMs != nil,
                        restartExpected: restartExpected, at: now
                    )
                    events += healthEvents(miner, info, &track.health, now: now)
                    events += payoutEvents(miner, info, &track, now: now)
                    logHealth(of: miner, info, &track.health, now: now)
                    let lastRestart = [changeLog.lastAutomaticRestart(host: miner.ipAddress), track.lastSkippedRestartAt]
                        .compactMap { $0 }.max()
                    if let reason = track.health.dueAutoRestart(
                        onFlatline: restartsOnFlatline, toPrimary: restartsToPrimary,
                        lastRestart: lastRestart, at: now
                    ) {
                        if isReadOnly() {
                            track.lastSkippedRestartAt = now
                            events.append(skippedRestartEvent(miner, reason))
                        } else {
                            restarts.append((miner, reason))
                        }
                    }
                }
            }
            tracks[miner.id] = track
        }
        for (miner, reason) in restarts {
            let result = await autoRestart(miner, reason)
            // The restart message names the same problem: one message, not two at once.
            events.removeAll { $0.minerID == miner.id && $0.kind == result.kind && !$0.isRecovery }
            events.append(result)
        }
        for index in events.indices {
            events[index].minerName = miners.first { $0.id == events[index].minerID }?.displayName ?? ""
        }

        let deliverable = events.filter { isEnabled && !isSilenced(at: now) && !isMuted($0.minerID) && isKindEnabled($0.kind) }
        for event in events {
            let address = miners.first { $0.id == event.minerID }?.ipAddress ?? "?"
            let delivered = deliverable.contains(event)
            DiagnosticLog.shared.write("alert", "\(address) \(event.kind.rawValue) \(event.isRecovery ? "cleared" : "raised") delivered=\(delivered ? 1 : 0)", at: now)
        }
        for event in AlertEvent.combine(deliverable) {
            await notifier.deliver(event)
        }
        return deliverable
    }

    /// Read-only mode wins over the watchdog, but the user should know a restart was left out.
    private func skippedRestartEvent(_ miner: MinerDevice, _ reason: MinerHealth.AutoRestartReason) -> AlertEvent {
        AlertEvent(
            kind: reason == .flatline ? .flatline : .fallback, minerID: miner.id,
            title: String(localized: "\(miner.displayName) was not restarted"),
            body: String(localized: "An automatic restart was due, but read-only mode is on."),
            isRecovery: false, standsAlone: true
        )
    }

    /// The watchdog's only action. Noted in the change log like any other write.
    private func autoRestart(_ miner: MinerDevice, _ reason: MinerHealth.AutoRestartReason) async -> AlertEvent {
        let name = miner.displayName
        let kind: AlertKind = reason == .flatline ? .flatline : .fallback
        let why = reason == .flatline
            ? String(localized: "No more shares.")
            : String(localized: "The primary pool is reachable again, but the miner stayed on the fallback pool.")
        do {
            try await ChangeLog.$source.withValue(.watchdog) { try await restartMiner(miner) }
            return AlertEvent(
                kind: kind, minerID: miner.id,
                title: String(localized: "\(name) was restarted automatically"),
                body: why, isRecovery: false, standsAlone: true
            )
        } catch {
            return AlertEvent(
                kind: kind, minerID: miner.id,
                title: String(localized: "\(name) could not be restarted"),
                body: "\(why) \(error.localizedDescription)", isRecovery: false, standsAlone: true
            )
        }
    }

    private func logState(of miner: MinerDevice, _ track: inout MinerTrack, now: Date) {
        if case .offline(let reason) = miner.connectionState, track.wasOnline != false {
            track.wasOnline = false
            DiagnosticLog.shared.write("state", "\(miner.ipAddress) offline: \(reason)", at: now)
        } else if miner.connectionState.isOnline, track.wasOnline != true {
            track.wasOnline = true
            DiagnosticLog.shared.write("state", "\(miner.ipAddress) online", at: now)
        }
    }

    private func logHealth(of miner: MinerDevice, _ info: MinerSystemInfo, _ health: inout MinerHealth, now: Date) {
        guard let snapshot = health.snapshot(info, at: now) else { return }
        DiagnosticLog.shared.write("health", "\(miner.ipAddress) \(snapshot)", at: now)
        let profile = DiagnosticLog.profile(miner, info)
        if profile != health.lastProfile {
            health.lastProfile = profile
            DiagnosticLog.shared.write("miner", "\(miner.ipAddress) \(profile)", at: now)
        }
    }

    private func healthEvents(_ miner: MinerDevice, _ info: MinerSystemInfo, _ health: inout MinerHealth, now: Date) -> [AlertEvent] {
        var events: [AlertEvent] = []
        let name = miner.displayName
        if health.isOverheating != health.overheatAlerted {
            let due = health.lastOverheatAlertAt.map { now.timeIntervalSince($0) >= Self.repeatInterval } ?? true
            if health.overheatAlerted {
                health.overheatAlerted = false
                events.append(AlertEvent(
                    kind: .overheat, minerID: miner.id,
                    title: String(localized: "\(name) has cooled down"),
                    body: String(localized: "The temperature is back to normal."),
                    isRecovery: true
                ))
            } else if due {
                health.overheatAlerted = true
                health.lastOverheatAlertAt = now
                let body = info.overheatMode
                    ? String(localized: "The miner has throttled itself and stays that way until it restarts. Check the cooling first.")
                    : String(localized: "ASIC \(Int(info.temp)) °C, voltage regulator \(Int(info.vrTemp ?? 0)) °C, limit \(Int(info.overheatTemp ?? 0)) °C. Check the cooling.")
                events.append(AlertEvent(
                    kind: .overheat, minerID: miner.id,
                    title: String(localized: "\(name) is overheating"),
                    body: body,
                    isRecovery: false
                ))
            }
        }
        if health.isFlatlining != health.flatlineAlerted {
            let due = health.lastFlatlineAlertAt.map { now.timeIntervalSince($0) >= Self.repeatInterval } ?? true
            if health.flatlineAlerted {
                health.flatlineAlerted = false
                events.append(AlertEvent(
                    kind: .flatline, minerID: miner.id,
                    title: String(localized: "\(name) is delivering shares again"),
                    body: String(localized: "New shares are arriving again."),
                    isRecovery: true
                ))
            } else if due {
                health.flatlineAlerted = true
                health.lastFlatlineAlertAt = now
                events.append(AlertEvent(
                    kind: .flatline, minerID: miner.id,
                    title: String(localized: "\(name) has stopped delivering shares"),
                    body: String(localized: "No new share for \(health.minutesWithoutShares(at: now)) min although the miner responds. A restart usually helps."),
                    isRecovery: false
                ))
            }
        }
        if health.isOnFallback != health.fallbackAlerted {
            let due = health.lastFallbackAlertAt.map { now.timeIntervalSince($0) >= Self.repeatInterval } ?? true
            if health.fallbackAlerted {
                health.fallbackAlerted = false
                events.append(AlertEvent(
                    kind: .fallback, minerID: miner.id,
                    title: String(localized: "\(name) is back on the primary pool"),
                    body: String(localized: "The miner is using its primary pool again."),
                    isRecovery: true
                ))
            } else if due {
                health.fallbackAlerted = true
                health.lastFallbackAlertAt = now
                events.append(AlertEvent(
                    kind: .fallback, minerID: miner.id,
                    title: String(localized: "\(name) is on the fallback pool"),
                    body: String(localized: "On \(info.activePoolHost) for at least 10 min. The primary pool may be down."),
                    isRecovery: false
                ))
            }
        }
        if health.isStuckOnFallback, !health.stuckAlerted {
            health.stuckAlerted = true
            events.append(AlertEvent(
                kind: .fallback, minerID: miner.id,
                title: String(localized: "\(name) does not switch back"),
                body: String(localized: "The primary pool has been reachable for 15 min, but the miner stays on the fallback pool. A restart brings it back."),
                isRecovery: false
            ))
        } else if !health.isOnFallback {
            health.stuckAlerted = false
        }
        if health.restartedUnexpectedly {
            let reason = info.resetReason.map { String(localized: "Reason given by the miner: \($0).") } ?? String(localized: "The miner gives no reason.")
            events.append(AlertEvent(
                kind: .restart, minerID: miner.id,
                title: String(localized: "\(name) restarted"),
                body: String(localized: "MinerGuru did not trigger this. \(reason)"),
                isRecovery: false
            ))
        }
        return events
    }

    /// Default or foreign addresses, addresses changed outside MinerGuru and blocks that skip the miner.
    private func payoutEvents(_ miner: MinerDevice, _ info: MinerSystemInfo, _ track: inout MinerTrack, now: Date) -> [AlertEvent] {
        var events: [AlertEvent] = []
        let name = miner.displayName
        let id = miner.id.uuidString
        let ownChange = changeLog.lastWrite(host: miner.ipAddress)
            .map { now.timeIntervalSince($0) < Self.ownChangeWindow } ?? false
        var seen = payoutMemory.seen[id] ?? [:]
        var alerted = payoutMemory.alerted[id] ?? [:]
        for slot in PayoutCheck.slots(of: info, expected: expectedAddresses) where !slot.address.isEmpty {
            let previous = seen[slot.key]
            seen[slot.key] = slot.address
            if let previous, previous != slot.address {
                alerted[slot.key] = slot.address
                if !ownChange {
                    events.append(AlertEvent(
                        kind: .payout, minerID: miner.id,
                        title: String(localized: "Address of \(name) was changed"),
                        body: String(localized: "\(slot.title): \(PayoutCheck.shortened(previous)) → \(PayoutCheck.shortened(slot.address)). This did not come from MinerGuru."),
                        isRecovery: false
                    ))
                }
            } else if slot.verdict.needsAttention, alerted[slot.key] != slot.address {
                alerted[slot.key] = slot.address
                events.append(AlertEvent(
                    kind: .payout, minerID: miner.id,
                    title: slot.verdict == .factoryDefault
                        ? String(localized: "\(name) uses a default address")
                        : String(localized: "\(name) pays to a foreign address"),
                    body: String(localized: "\(slot.title): \(PayoutCheck.shortened(slot.address)). A block found would not go to you."),
                    isRecovery: false
                ))
            }
        }
        if payoutMemory.seen[id] != seen || payoutMemory.alerted[id] != alerted {
            payoutMemory.seen[id] = seen
            payoutMemory.alerted[id] = alerted
            savePayoutMemory()
        }

        track.payoutMissPolls = PayoutCheck.blockSkipsMiner(info) ? track.payoutMissPolls + 1 : 0
        if track.payoutMissPolls == 0 {
            track.payoutMissAlerted = false
        } else if track.payoutMissPolls >= Self.payoutMissPolls, !track.payoutMissAlerted {
            track.payoutMissAlerted = true
            events.append(AlertEvent(
                kind: .payout, minerID: miner.id,
                title: String(localized: "Block does not pay \(name)"),
                body: String(localized: "The pool's block template does not contain the miner's address. Check the pool settings."),
                isRecovery: false
            ))
        }
        return events
    }

    /// Sends alerts that do not come from polling, such as due maintenance.
    func deliver(_ events: [AlertEvent]) async {
        guard isEnabled, !isSilenced() else { return }
        for event in AlertEvent.combine(events.filter { isKindEnabled($0.kind) }) {
            await notifier.deliver(event)
        }
    }

    // MARK: - App Nap

    private func updateAppNapGuard() {
        guard guardsAppNap else { return }
        if isEnabled, appNapActivity == nil {
            appNapActivity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep,
                reason: "Miner monitoring for notifications"
            )
        } else if !isEnabled, let activity = appNapActivity {
            ProcessInfo.processInfo.endActivity(activity)
            appNapActivity = nil
        }
    }
}
