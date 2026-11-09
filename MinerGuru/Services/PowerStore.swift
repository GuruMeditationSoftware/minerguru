import Foundation

/// The miner's own clock and fan settings, saved before a schedule changes them and written back afterwards.
struct SavedMinerSettings: Codable, Sendable, Equatable {
    var frequencyMHz: Int
    var coreVoltageMV: Int
    var autoFanMode: Int
    var fanPercent: Int

    init(info: MinerSystemInfo) {
        frequencyMHz = info.frequencyMHz
        coreVoltageMV = info.coreVoltageTargetMV
        autoFanMode = info.autoFanSpeed ? max(1, info.autoFanModeRaw) : 0
        fanPercent = Int(info.fanSpeedPercent.rounded())
    }

    var payload: MinerSystemUpdatePayload {
        MinerSystemUpdatePayload(
            frequency: frequencyMHz,
            coreVoltage: coreVoltageMV,
            autofanspeed: autoFanMode,
            fanspeed: autoFanMode == 0 ? fanPercent : nil
        )
    }
}

/// What the schedules last did to one miner.
struct MinerPowerState: Codable, Sendable, Equatable {
    var action: PowerAction
    var since: Date
    /// Settings before the night mode, restored on the way back to normal.
    var saved: SavedMinerSettings?
    /// Switched by the manual night mode (Control Center), not by a schedule.
    var isManual: Bool? = nil
}

/// Tariff, schedules and their execution (MG-14). After every refresh round it checks which action the rules ask for
/// and switches the miners that are not in that state yet, at most once per `minimumSwitchInterval`.
@MainActor
final class PowerStore: ObservableObject {
    @Published var tariff: PowerTariff { didSet { save(tariff, Self.tariffKey) } }
    @Published var rules: [ScheduleRule] {
        didSet { save(rules, Self.rulesKey); updateAppNapGuard(); scheduleEvaluation() }
    }
    /// Only one device should switch the miners, otherwise the Mac and the phone work against each other.
    @Published var runsSchedules: Bool {
        didSet { defaults.set(runsSchedules, forKey: Self.runsKey); updateAppNapGuard(); scheduleEvaluation() }
    }
    /// Night mode for all miners right now, switched by hand (Control Center or the power page).
    /// It wins over the schedules, except that a scheduled pause stays a pause.
    @Published var manualNight: Bool {
        didSet {
            guard manualNight != oldValue else { return }
            defaults.set(manualNight, forKey: Self.manualNightKey)
            manualNightChangedAt = Date()
            scheduleEvaluation()
        }
    }
    /// Fixed fan speed of the night mode, in percent.
    @Published var nightFanPercent: Int { didSet { defaults.set(nightFanPercent, forKey: Self.nightFanKey) } }
    @Published private(set) var states: [UUID: MinerPowerState] { didSet { save(states, Self.statesKey) } }
    @Published private(set) var lastError: String?

    static let minimumSwitchInterval: TimeInterval = 15 * 60

    private let defaults: UserDefaults
    private weak var minerStore: MinerStore?
    private var switching: Set<UUID> = []
    private var appNapActivity: NSObjectProtocol?
    private let backgroundWorkEnabled: Bool
    /// A manual switch skips the minimum interval: the user wants to see it happen now.
    private var manualNightChangedAt: Date?

    private static let tariffKey = "MinerGuru.PowerTariff.v1"
    private static let rulesKey = "MinerGuru.PowerRules.v1"
    private static let runsKey = "MinerGuru.PowerRunsSchedules.v1"
    private static let nightFanKey = "MinerGuru.PowerNightFan.v1"
    private static let statesKey = "MinerGuru.PowerStates.v1"
    private static let manualNightKey = "MinerGuru.PowerManualNight.v1"

    init(defaults: UserDefaults, startBackgroundWork: Bool) {
        self.defaults = defaults
        self.backgroundWorkEnabled = startBackgroundWork
        tariff = Self.load(PowerTariff.self, Self.tariffKey, defaults) ?? .default
        rules = Self.load([ScheduleRule].self, Self.rulesKey, defaults) ?? []
        states = Self.load([UUID: MinerPowerState].self, Self.statesKey, defaults) ?? [:]
        runsSchedules = defaults.object(forKey: Self.runsKey) == nil ? true : defaults.bool(forKey: Self.runsKey)
        manualNight = defaults.bool(forKey: Self.manualNightKey)
        let fan = defaults.integer(forKey: Self.nightFanKey)
        nightFanPercent = fan > 0 ? fan : 40
    }

    /// The store calls `evaluate()` after every refresh round, so schedules switch as soon as the miners answer.
    func attach(to store: MinerStore) {
        minerStore = store
        updateAppNapGuard()
    }

    // MARK: - Tariff and rules

    func zone(id: UUID) -> TariffZone? { tariff.zones.first { $0.id == id } }

    func removeZone(id: UUID) {
        tariff.zones.removeAll { $0.id == id }
        // A rule without its zone would never apply again.
        rules.removeAll { $0.trigger == .zone(id) }
    }

    /// A rule keeps its last miner: an empty set would mean all miners. It then applies to none and shows "Miner entfernt".
    func forget(minerID: UUID) {
        states[minerID] = nil
        for i in rules.indices where rules[i].minerIDs.count > 1 { rules[i].minerIDs.remove(minerID) }
    }

    func state(for minerID: UUID) -> PowerAction { states[minerID]?.action ?? .normal }

    func plannedAction(for minerID: UUID, at date: Date = Date()) -> PowerAction {
        PowerSchedule.action(for: minerID, at: date, rules: rules, tariff: tariff)
    }

    /// Pause needs AxeOS 2.15+; there `pools[]` is present.
    static func canPause(_ miner: MinerDevice) -> Bool {
        miner.latestInfo?.firmware == .axeOS && miner.latestInfo?.axePools != nil
    }

    /// The action really used for `miner`: pause becomes night mode where the firmware cannot pause (unknown while offline).
    static func effective(_ action: PowerAction, for miner: MinerDevice) -> PowerAction {
        action == .pause && miner.latestInfo != nil && !canPause(miner) ? .nightMode : action
    }

    // MARK: - Costs

    /// Cost per hour at the current draw and price.
    func costPerHour(watts: Double, at date: Date = Date()) -> Double {
        watts / 1000 * tariff.price(at: date)
    }

    /// Cost of the next `hours` at the current draw, with the prices and pauses of the plan.
    func projectedCost(for miner: MinerDevice, hours: Double, from start: Date = Date()) -> Double {
        PowerSchedule.cost(watts: miner.latestInfo?.power ?? 0, from: start, hours: hours, tariff: tariff,
                           rules: rules, minerID: miner.id, canPause: Self.canPause(miner))
    }

    /// Cost of today, from midnight to midnight, at the current draw.
    func costToday(for miner: MinerDevice, calendar: Calendar = .current) -> Double {
        projectedCost(for: miner, hours: 24, from: calendar.startOfDay(for: Date()))
    }

    // MARK: - Execution

    private func scheduleEvaluation() {
        guard backgroundWorkEnabled, minerStore != nil else { return }
        Task { await evaluate() }
    }

    /// What this Mac wants `minerID` to run now, or `nil` if it leaves the miner alone.
    func wantedAction(for minerID: UUID, at date: Date = Date()) -> PowerAction? {
        let planned = runsSchedules ? plannedAction(for: minerID, at: date) : .normal
        if manualNight { return planned == .pause ? .pause : .nightMode }
        if runsSchedules { return planned }
        // Without schedules this Mac only undoes its own manual night mode.
        return states[minerID]?.isManual == true ? .normal : nil
    }

    /// Switches every online miner whose state differs from what the rules and the manual night mode ask for now.
    func evaluate(at date: Date = Date()) async {
        guard let store = minerStore else { return }
        for miner in store.onlineMiners {
            guard let planned = wantedAction(for: miner.id, at: date) else { continue }
            let wanted = Self.effective(planned, for: miner)
            let current = states[miner.id]
            guard (current?.action ?? .normal) != wanted, !switching.contains(miner.id) else { continue }
            let manualSwitch = manualNightChangedAt.map { changed in current.map { changed > $0.since } ?? true } ?? false
            if let current, !manualSwitch, date.timeIntervalSince(current.since) < Self.minimumSwitchInterval { continue }
            // No request without a session: repeated refusals would lock the miner.
            guard store.otp.canWriteUnattended(miner, at: date) else { continue }
            await switchMiner(miner, to: wanted, at: date)
        }
    }

    private func switchMiner(_ miner: MinerDevice, to action: PowerAction, at date: Date) async {
        guard let info = miner.latestInfo else { return }
        switching.insert(miner.id)
        defer { switching.remove(miner.id) }

        let client = MinerAPIClient.shared
        let previous = states[miner.id]
        let host = miner.ipAddress
        do {
            // Leave the old state first.
            if previous?.action == .pause {
                try await client.resumeMiner(host: host)
            }
            var saved = previous?.saved
            switch action {
            case .normal:
                if let saved {
                    try await applySettings(saved.payload, to: miner)
                }
                saved = nil
            case .nightMode:
                if saved == nil { saved = SavedMinerSettings(info: info) }
                try await applySettings(nightPayload(for: miner, saved: saved!), to: miner)
            case .pause:
                // Night values stay until `.normal`: restoring them restarts AxeOS, and the restart would end the pause.
                try await client.pauseMiner(host: host)
            }
            states[miner.id] = action == .normal && saved == nil
                ? MinerPowerState(action: .normal, since: date)
                : MinerPowerState(action: action, since: date, saved: saved, isManual: manualNight ? true : nil)
            lastError = nil
            Log.miner.info("Schedule: \(host, privacy: .public) → \(action.rawValue, privacy: .public)")
        } catch {
            lastError = String(localized: "\(miner.displayName): \(error.localizedDescription)")
            Log.miner.error("Schedule for \(host, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Eco clock and the fixed night fan speed.
    private func nightPayload(for miner: MinerDevice, saved: SavedMinerSettings) -> MinerSystemUpdatePayload {
        let eco = miner.recommendedPresets.first { $0.name == "Eco" }
        return MinerSystemUpdatePayload(
            frequency: min(eco?.frequencyMHz ?? saved.frequencyMHz, saved.frequencyMHz),
            coreVoltage: min(eco?.coreVoltageMV ?? saved.coreVoltageMV, saved.coreVoltageMV),
            autofanspeed: 0,
            fanspeed: nightFanPercent
        )
    }

    /// AxeOS uses new clock settings only after a reboot, NerdOS at once.
    private func applySettings(_ payload: MinerSystemUpdatePayload, to miner: MinerDevice) async throws {
        guard let store = minerStore else { return }
        try await store.writeSettings(payload, to: miner, interactive: false)
        if !miner.isNerdOS {
            try await MinerAPIClient.shared.restartMiner(host: miner.ipAddress)
        }
    }

    // MARK: - App Nap

    /// Keeps macOS from throttling the polling (and with it the schedules) while there are schedules to run.
    private func updateAppNapGuard() {
        guard backgroundWorkEnabled else { return }
        let needed = runsSchedules && rules.contains(where: \.isEnabled)
        if needed, appNapActivity == nil {
            appNapActivity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep,
                reason: "Miner schedules"
            )
        } else if !needed, let activity = appNapActivity {
            ProcessInfo.processInfo.endActivity(activity)
            appNapActivity = nil
        }
    }

    // MARK: - Persistence

    private func save<T: Encodable>(_ value: T, _ key: String) {
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: key)
        } catch {
            Log.persistence.error("Power settings not savable: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String, _ defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            Log.persistence.error("Power settings not readable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
