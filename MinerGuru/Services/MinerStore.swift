import Foundation
import Combine
import SwiftUI

enum SidebarSelection: Hashable {
    case overview
    case pools
    case power
    case maintenance
    case reports
    case miner(UUID)
}

/// Total hashrate of all online miners after one refresh round.
struct FleetHashrateSample: Identifiable, Equatable, Sendable {
    var timestamp: Date
    var hashRateGHs: Double
    var onlineCount: Int

    var id: Date { timestamp }
}

@MainActor
final class MinerStore: ObservableObject {
    @Published var miners: [MinerDevice] = []
    @Published var selection: SidebarSelection? = .overview
    @Published var isRefreshingAll: Bool = false
    @Published var lastGlobalRefresh: Date?
    /// Fleet hashrate per refresh round, for the overview chart (kept in memory like the miners' history).
    @Published private(set) var fleetHistory: [FleetHashrateSample] = []

    // MARK: - Settings
    @Published var pollingIntervalSeconds: Int {
        didSet {
            defaults.set(pollingIntervalSeconds, forKey: Self.pollingIntervalKey)
            restartPollingLoop()
        }
    }

    @Published var tempWarningThresholdC: Double {
        didSet {
            defaults.set(tempWarningThresholdC, forKey: Self.tempWarningKey)
        }
    }

    @Published var autoScanOnEmptyLaunch: Bool {
        didSet {
            defaults.set(autoScanOnEmptyLaunch, forKey: Self.autoScanKey)
        }
    }

    /// Stratum probe (MG-04): read the block template from the pool for miners that do not report it. Off until switched on.
    @Published var stratumProbeEnabled: Bool {
        didSet {
            defaults.set(stratumProbeEnabled, forKey: Self.stratumProbeKey)
            if !stratumProbeEnabled { blockProbes.reset() }
        }
    }

    // MARK: - Sheets
    @Published var showScannerSheet: Bool = false
    @Published var showAddIPSheet: Bool = false

    // MARK: - Sub-stores
    /// Timeframe of the solo-mining chance on the dashboard.
    @Published var soloChanceTimeframe: SoloChanceTimeframe {
        didSet { defaults.set(soloChanceTimeframe.rawValue, forKey: Self.soloTimeframeKey) }
    }
    /// Saved pool configurations.
    let poolLibrary: PoolLibraryStore
    /// Notifications about miner problems.
    let alerts: AlertCenter
    /// Block templates read by the Stratum probe.
    let blockProbes = BlockProbeStore()
    /// Tariff, power costs and schedules.
    let power: PowerStore
    let otp: OtpSessions
    let poolSchedules: PoolScheduleStore
    let maintenance: MaintenanceStore
    let updates: UpdateChecker
    let history: HistoryStore
    let email: EmailAlertSettings
    /// Local subnet scan.
    private(set) lazy var scanner = NetworkScanStore(minerStore: self)

    // MARK: - Status Banner / Feedback
    @Published var statusBannerMessage: String?
    @Published var statusBannerIsError: Bool = false

    private var pollingTask: Task<Void, Never>?
    /// Failed polls right after the Mac woke do not count, see `WakeGrace`.
    private var wakeGrace = WakeGrace()
    /// Both clocks for `WakeGrace` in seconds; replaced in tests.
    var wakeClocks: () -> (wall: TimeInterval, awake: TimeInterval) = { (WakeGrace.wallSeconds, WakeGrace.awakeSeconds) }
    /// Switches that the widgets and controls show, watched to update them at once.
    private var widgetWatchers: Set<AnyCancellable> = []
    private let defaults: UserDefaults
    /// Polling, scans and network refreshes; off in unit tests.
    private let backgroundWorkEnabled: Bool

    private static let savedMinersKey = "MinerGuru.SavedMiners.v1"
    private static let pollingIntervalKey = "MinerGuru.PollingIntervalSeconds.v1"
    private static let tempWarningKey = "MinerGuru.TempWarningThresholdC.v1"
    private static let autoScanKey = "MinerGuru.AutoScanOnEmptyLaunch.v1"
    private static let soloTimeframeKey = "MinerGuru.SoloChanceTimeframe.v1"
    private static let stratumProbeKey = "MinerGuru.StratumProbeEnabled.v1"
    static let maxHistorySamples = 240

    /// - Parameters:
    ///   - defaults: Storage for settings and the miner list (tests pass an isolated suite).
    ///   - startBackgroundWork: Starts polling and the first-launch scan. Disabled in tests.
    init(
        defaults: UserDefaults = .standard,
        startBackgroundWork: Bool = true,
        alerts: AlertCenter? = nil,
        history: HistoryStore? = nil
    ) {
        self.defaults = defaults
        self.soloChanceTimeframe = defaults.string(forKey: Self.soloTimeframeKey)
            .flatMap(SoloChanceTimeframe.init(rawValue:)) ?? .perDay
        self.poolLibrary = PoolLibraryStore(defaults: defaults)
        let email = EmailAlertSettings(defaults: defaults, readsKeychain: startBackgroundWork)
        self.email = email
        self.alerts = alerts ?? AlertCenter(
            defaults: defaults,
            notifier: EmailAlertNotifier(base: UserNotificationNotifier(), settings: email),
            guardsAppNap: startBackgroundWork
        )
        self.history = history ?? HistoryStore(path: startBackgroundWork ? HistoryStore.defaultPath : nil)
        self.poolSchedules = PoolScheduleStore(defaults: defaults)
        self.otp = OtpSessions(usesKeychain: startBackgroundWork)
        self.maintenance = MaintenanceStore(defaults: defaults)
        self.updates = UpdateChecker(defaults: defaults)
        self.backgroundWorkEnabled = startBackgroundWork
        self.power = PowerStore(defaults: defaults, startBackgroundWork: startBackgroundWork)

        let storedInterval = defaults.integer(forKey: Self.pollingIntervalKey)
        self.pollingIntervalSeconds = storedInterval > 0 ? storedInterval : 5

        let storedTemp = defaults.double(forKey: Self.tempWarningKey)
        self.tempWarningThresholdC = storedTemp > 0 ? storedTemp : 68.0

        self.autoScanOnEmptyLaunch = defaults.object(forKey: Self.autoScanKey) == nil
            ? true
            : defaults.bool(forKey: Self.autoScanKey)

        self.stratumProbeEnabled = defaults.bool(forKey: Self.stratumProbeKey)

        loadPersistedMiners()
        power.attach(to: self)
        poolSchedules.attach(to: self)
        watchHistory()
        #if DEBUG
        // Opens a page right away, for looking at it without clicking there.
        switch ProcessInfo.processInfo.environment["MINERGURU_OPEN"] {
        case "pools": selection = .pools
        case "power": selection = .power
        case "maintenance": selection = .maintenance
        case "reports": selection = .reports
        case "miner": selection = miners.first.map { .miner($0.id) }
        default: break
        }
        #endif

        guard startBackgroundWork else { return }
        watchWidgetSwitches()
        startPollingLoop()
        updates.start()
        if miners.isEmpty && autoScanOnEmptyLaunch {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                self?.scanner.startScan(autoAddNew: false)
            }
        }
    }

    // MARK: - Fleet Aggregations

    /// Appends the current fleet hashrate to `fleetHistory`, capped like a miner's history.
    func recordFleetSample(at date: Date = Date()) {
        fleetHistory.append(FleetHashrateSample(timestamp: date, hashRateGHs: totalHashrateGHs, onlineCount: onlineMiners.count))
        if fleetHistory.count > Self.maxHistorySamples {
            fleetHistory.removeFirst(fleetHistory.count - Self.maxHistorySamples)
        }
    }

    var onlineMiners: [MinerDevice] {
        miners.filter { $0.connectionState.isOnline && $0.latestInfo != nil }
    }

    var totalHashrateGHs: Double {
        onlineMiners.reduce(0) { $0 + ($1.latestInfo?.hashRate ?? 0) }
    }

    var totalPowerWatts: Double {
        onlineMiners.reduce(0) { $0 + ($1.latestInfo?.power ?? 0) }
    }

    var fleetEfficiencyJPerTH: Double {
        let totalTH = totalHashrateGHs / 1000.0
        guard totalTH > 0.01, totalPowerWatts > 0 else { return 0 }
        return totalPowerWatts / totalTH
    }

    var totalSharesAccepted: Int {
        onlineMiners.reduce(0) { $0 + ($1.latestInfo?.sharesAccepted ?? 0) }
    }

    var totalSharesRejected: Int {
        onlineMiners.reduce(0) { $0 + ($1.latestInfo?.sharesRejected ?? 0) }
    }

    var highestBestDiffFormatted: String {
        guard let bestMiner = onlineMiners.max(by: {
            ($0.latestInfo?.bestDiffNumeric ?? 0) < ($1.latestInfo?.bestDiffNumeric ?? 0)
        }), let info = bestMiner.latestInfo else {
            return "—"
        }
        return info.bestDiffFormatted
    }

    var averagePoolLatencyMs: Double? {
        let latencies = onlineMiners.compactMap { $0.activePoolLatencyMs }.filter { $0 > 0 }
        guard !latencies.isEmpty else { return nil }
        return latencies.reduce(0, +) / Double(latencies.count)
    }

    /// Hashrate, network difficulty and solo-mining odds per coin across all online miners.
    var activeFleetCoinSummaries: [FleetCoinMiningSummary] {
        FleetCoinMiningSummary.summaries(for: onlineMiners)
    }

    var menuBarSummaryText: String {
        guard !miners.isEmpty else { return "MinerGuru" }
        if onlineMiners.isEmpty {
            return "Offline"
        }
        return MinerFormatting.formatHashrate(totalHashrateGHs)
    }

    // MARK: - Persistence

    private func loadPersistedMiners() {
        guard let data = defaults.data(forKey: Self.savedMinersKey) else {
            miners = []
            return
        }
        do {
            let configs = try JSONDecoder().decode([PersistedMinerConfig].self, from: data)
            miners = configs.map { MinerDevice(config: $0, connectionState: .checking) }
        } catch {
            Log.persistence.error("Saved miner list not readable: \(error.localizedDescription, privacy: .public)")
            miners = []
        }
    }

    func saveMiners() {
        do {
            let data = try JSONEncoder().encode(miners.map(\.persistedConfig))
            defaults.set(data, forKey: Self.savedMinersKey)
        } catch {
            Log.persistence.error("Miner list could not be saved: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Miner CRUD

    func isIPAlreadyAdded(_ ip: String) -> Bool {
        let normalized = MinerAPIClient.normalizeHost(ip).lowercased()
        return miners.contains { $0.ipAddress.lowercased() == normalized }
    }

    @discardableResult
    func addMiner(
        ipAddress rawIP: String,
        customName: String? = nil,
        initialInfo: MinerSystemInfo? = nil,
        rawJSON: String? = nil
    ) -> MinerDevice? {
        let ip = MinerAPIClient.normalizeHost(rawIP)
        guard !ip.isEmpty else { return nil }

        if let existingIdx = miners.firstIndex(where: { $0.ipAddress.lowercased() == ip.lowercased() }) {
            if let customName, !customName.isEmpty {
                var updated = miners
                updated[existingIdx].customName = customName
                miners = updated
                saveMiners()
            }
            return miners[existingIdx]
        }

        let trimmedName = customName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = PersistedMinerConfig(
            ipAddress: ip,
            customName: (trimmedName?.isEmpty == false) ? trimmedName : nil,
            cachedHostname: initialInfo?.hostname,
            cachedHardwareModel: initialInfo?.detectedHardwareTitle
        )

        var device = MinerDevice(
            config: config,
            connectionState: initialInfo != nil ? .online : .checking,
            latestInfo: initialInfo,
            rawJSON: rawJSON
        )

        if let info = initialInfo {
            device.lastSeenAt = Date()
            let sample = MinerTelemetrySample(
                hashRateGHs: info.hashRate,
                asicTempC: info.temp,
                vrTempC: info.vrTemp,
                powerWatts: info.power,
                poolLatencyMs: info.minerReportedPoolLatencyMs,
                fanPercent: info.fanSpeedPercent
            )
            device.history.append(sample)
        }

        var updated = miners
        updated.append(device)
        updated.sort { NetworkScanner.ipSortKey($0.ipAddress) < NetworkScanner.ipSortKey($1.ipAddress) }
        miners = updated
        saveMiners()

        if backgroundWorkEnabled {
            Task { await refreshMiner(id: device.id) }
        }
        return device
    }

    func removeMiner(id: UUID) {
        if selection == .miner(id) {
            selection = .overview
        }
        miners.removeAll { $0.id == id }
        alerts.forget(minerID: id)
        power.forget(minerID: id)
        poolSchedules.forget(minerID: id)
        otp.invalidate(id)
        maintenance.forget(minerID: id)
        history.forget(minerID: id)
        saveMiners()
        // Polling stops with the last miner, so the widgets would keep showing it.
        Task { await WidgetBridge.shared.publish() }
    }

    func updateMinerCustomName(id: UUID, customName: String?) {
        guard let idx = miners.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = customName?.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = miners
        updated[idx].customName = (trimmed?.isEmpty == false) ? trimmed : nil
        miners = updated
        saveMiners()
    }

    // MARK: - Polling & Telemetry Refresh

    func startPollingLoop() {
        // The test host must not talk to the miners saved on this machine.
        guard !MinerGuruApp.isRunningTests else { return }
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            await self?.refreshAllMiners()
            while !Task.isCancelled {
                guard let seconds = self?.pollingIntervalSeconds else { return }
                try? await Task.sleep(for: .seconds(max(2, seconds)))
                guard !Task.isCancelled else { return }
                await self?.refreshAllMiners()
            }
        }
    }

    func restartPollingLoop() {
        startPollingLoop()
    }

    struct SingleMinerFetchResult: Sendable {
        let id: UUID
        let info: MinerSystemInfo?
        let rawJSON: String?
        let latency: PoolLatencyMeasurement?
        let errorDescription: String?
    }

    func refreshAllMiners() async {
        guard !miners.isEmpty else { return }
        isRefreshingAll = true

        let targets: [(id: UUID, host: String)] = miners.map { ($0.id, $0.ipAddress) }

        let results = await withTaskGroup(of: SingleMinerFetchResult.self, returning: [SingleMinerFetchResult].self) { group in
            for target in targets {
                group.addTask { await Self.fetch(id: target.id, host: target.host) }
            }

            var collected: [SingleMinerFetchResult] = []
            for await res in group {
                collected.append(res)
            }
            return collected
        }

        // Apply all updates in a single batch on MainActor to avoid multiple layout passes per frame
        var updated = miners
        var needsSave = false
        // Right after a wake the network is not back yet. A miner that does not answer then keeps its
        // last state and stays out of the history and the alarms for this poll.
        let ignoresFailures = noteWake()
        var unanswered: Set<UUID> = []

        for res in results {
            guard let idx = updated.firstIndex(where: { $0.id == res.id }) else { continue }
            if ignoresFailures, res.info == nil {
                unanswered.insert(res.id)
                DiagnosticLog.shared.write("state", "\(updated[idx].ipAddress) no answer right after wake, not counted")
                continue
            }
            if Self.apply(res, to: &updated[idx]) {
                needsSave = true
            }
        }

        miners = updated
        lastGlobalRefresh = Date()
        isRefreshingAll = false
        recordFleetSample()

        if needsSave {
            saveMiners()
        }
        history.record(historyReadings().filter { !unanswered.contains($0.minerID) })
        await alerts.evaluate(miners.filter { !unanswered.contains($0.id) })
        await alerts.deliver(maintenance.dueEvents())
        if backgroundWorkEnabled {
            await WidgetBridge.shared.publish()
        }
        // Switch in the background, so a miner's reboot does not hold up the next poll.
        Task { await ChangeLog.$source.withValue(.schedule) { await power.evaluate() } }
        Task { await ChangeLog.$source.withValue(.schedule) { await poolSchedules.evaluate() } }
    }

    /// Notes sleep since the last poll. True while a failed poll comes too soon after a wake to count.
    private func noteWake() -> Bool {
        let clocks = wakeClocks()
        if let slept = wakeGrace.observe(wall: clocks.wall, awake: clocks.awake) {
            DiagnosticLog.shared.write("app", "wake after sleep=\(Int(slept))s")
        }
        return wakeGrace.isActive(wall: clocks.wall)
    }

    /// What the last poll saw, for the long-term history.
    func historyReadings(at date: Date = Date()) -> [HistoryStore.Reading] {
        miners.compactMap { miner in
            guard miner.connectionState.isOnline, let info = miner.latestInfo else {
                if case .offline = miner.connectionState {
                    return HistoryStore.Reading(minerID: miner.id, date: date, isOnline: false)
                }
                return nil
            }
            return HistoryStore.Reading(
                minerID: miner.id, date: date, isOnline: true, hashRateGHs: info.hashRate, asicTempC: info.temp,
                vrTempC: info.vrTemp, powerWatts: info.power, fanPercent: info.fanSpeedPercent,
                poolLatencyMs: miner.activePoolLatencyMs, errorPercent: info.errorPercentage,
                sharesAccepted: info.sharesAccepted, sharesRejected: info.sharesRejected, bestDiff: info.bestSessionDiffNumeric
            )
        }
    }

    func refreshMiner(id: UUID) async {
        guard let host = miners.first(where: { $0.id == id })?.ipAddress else { return }
        let result = await Self.fetch(id: id, host: host)

        // The miner may have been removed while the request was running.
        guard let idx = miners.firstIndex(where: { $0.id == id }) else { return }
        var updated = miners
        let needsSave = Self.apply(result, to: &updated[idx])
        miners = updated
        if needsSave {
            saveMiners()
        }
    }

    // MARK: - Fetch & apply (shared by single and fleet refresh)

    /// Fetches telemetry and pool latency for one miner. Never throws: failures become an offline result.
    private nonisolated static func fetch(id: UUID, host: String) async -> SingleMinerFetchResult {
        do {
            let (info, rawJSON) = try await MinerAPIClient.shared.fetchSystemInfo(host: host)
            let latency = await PoolLatencyService.shared.measureForMiner(info: info)
            return SingleMinerFetchResult(id: id, info: info, rawJSON: rawJSON, latency: latency, errorDescription: nil)
        } catch {
            Log.miner.debug("\(host, privacy: .public) unreachable: \(error.localizedDescription, privacy: .public)")
            return SingleMinerFetchResult(id: id, info: nil, rawJSON: nil, latency: nil, errorDescription: error.localizedDescription)
        }
    }

    /// Writes a fetch result into the device (state, telemetry, history sample).
    /// Returns `true` if persisted fields (hostname, hardware model) changed and the miner list should be saved.
    static func apply(_ result: SingleMinerFetchResult, to device: inout MinerDevice) -> Bool {
        guard let info = result.info, let latency = result.latency else {
            device.connectionState = .offline(reason: result.errorDescription ?? String(localized: "Nicht erreichbar"))
            return false
        }

        let now = Date()
        device.latestInfo = info
        device.rawJSON = result.rawJSON
        ChangeLog.shared.noteValues(host: device.ipAddress, rawJSON: result.rawJSON)
        device.poolLatency = latency
        device.connectionState = .online
        device.lastSeenAt = now

        var persistedChanged = false
        if device.cachedHostname != info.hostname || device.cachedHardwareModel != info.detectedHardwareTitle {
            device.cachedHostname = info.hostname
            device.cachedHardwareModel = info.detectedHardwareTitle
            persistedChanged = true
        }

        device.history.append(MinerTelemetrySample(
            timestamp: now,
            hashRateGHs: info.hashRate,
            asicTempC: info.temp,
            vrTempC: info.vrTemp,
            powerWatts: info.power,
            poolLatencyMs: latency.effectiveLatencyMs(usingFallback: info.isUsingFallbackStratum),
            fanPercent: info.fanSpeedPercent
        ))
        if device.history.count > maxHistorySamples {
            device.history.removeFirst(device.history.count - maxHistorySamples)
        }
        return persistedChanged
    }

    // MARK: - Miner Control Actions

    /// Writes settings to a miner, with a one-time code session where it demands one.
    /// Schedules pass `interactive: false`: they never ask and only use a stored session.
    func writeSettings(_ payload: MinerSystemUpdatePayload, to miner: MinerDevice, interactive: Bool = true) async throws {
        try await otp.perform(for: miner, interactive: interactive) { token in
            try await MinerAPIClient.shared.updateSystemSettings(host: miner.ipAddress, payload: payload, otpSession: token)
        }
    }

    /// Online miners with a one-time code and an enabled schedule that cannot run for lack of a session.
    var minersAwaitingOtp: [MinerDevice] {
        onlineMiners.filter { miner in
            !otp.canWriteUnattended(miner)
                && (power.rules.contains { $0.isEnabled && $0.applies(to: miner.id) }
                    || poolSchedules.rules.contains { $0.isEnabled && $0.applies(to: miner.id) })
        }
    }

    func updateMinerSettings(
        minerID: UUID,
        payload: MinerSystemUpdatePayload
    ) async throws {
        guard let miner = miners.first(where: { $0.id == minerID }) else { return }
        try await confirm(payload, on: miner)
        try await writeSettings(payload, to: miner)
        showBanner(String(localized: "Einstellungen an \(miner.displayName) übertragen."), isError: false)
        try? await Task.sleep(for: .milliseconds(600))
        await refreshMiner(id: minerID)
    }

    /// Writes the pool part of `form` to the miner, empties slots the user cleared (AxeOS 2.15+)
    /// and restarts the miner: AxeOS only stores pool changes and uses them after a reboot.
    func applyPoolSettings(_ form: MinerSettingsForm, minerID: UUID, interactive: Bool = true) async throws {
        guard let miner = miners.first(where: { $0.id == minerID }) else { return }
        let payload = form.poolPayload(supportsDualPool: miner.supportsDualPool)
        if interactive { try await confirm(payload, on: miner, clearing: form.slotsToClear, restarts: true) }
        try await writeSettings(payload, to: miner, interactive: interactive)
        for slot in form.slotsToClear {
            try await MinerAPIClient.shared.deletePoolSlot(host: miner.ipAddress, index: slot)
        }
        try await MinerAPIClient.shared.restartMiner(host: miner.ipAddress)
        showBanner(String(localized: "Pool-Konfiguration an \(miner.displayName) übertragen – Miner startet neu."), isError: false)
        if let idx = miners.firstIndex(where: { $0.id == minerID }) {
            miners[idx].connectionState = .checking
        }
        // Wait until the miner answers again, so the caller reloads the configuration it really uses.
        try? await Task.sleep(for: .seconds(5))
        for _ in 0..<10 {
            try? await Task.sleep(for: .seconds(3))
            await refreshMiner(id: minerID)
            if miners.first(where: { $0.id == minerID })?.connectionState.isOnline == true { break }
        }
    }

    /// Asks before a write by hand, with the values it replaces. Schedules were agreed to when they were set up.
    private func confirm(_ payload: MinerSystemUpdatePayload, on miner: MinerDevice, clearing slots: [Int] = [], restarts: Bool = false) async throws {
        if ChangeLog.isReadOnly { throw MinerAPIError.readOnly }
        let body = try JSONEncoder().encode(payload)
        var fields = ChangeLog.changes(body: body, current: ChangeLog.flatten(rawJSON: miner.rawJSON ?? "") ?? [:])
        fields += slots.map { ChangeField(key: "pools.\($0).stratumURL", before: nil, after: String(localized: "(geleert)")) }
        guard await confirmWrite(miner, fields, restarts) else { throw CancellationError() }
    }

    /// A dialog with old and new values; replaced in tests.
    var confirmWrite: @MainActor (MinerDevice, [ChangeField], Bool) async -> Bool = { miner, fields, restarts in
        MinerStore.askBeforeWriting(miner, fields, restarts: restarts)
    }

    private static func askBeforeWriting(_ miner: MinerDevice, _ fields: [ChangeField], restarts: Bool) -> Bool {
        var lines = fields.map(\.summary)
        if lines.isEmpty { lines = [String(localized: "Es ändert sich kein Wert.")] }
        if restarts { lines.append(String(localized: "Danach startet der Miner neu.")) }
        let text = lines.joined(separator: "\n")
        let alert = NSAlert()
        alert.messageText = String(localized: "An \(miner.displayName) übertragen?")
        alert.informativeText = UserDefaults.standard.bool(forKey: PrivacyMode.storageKey) ? PrivacyMode.scrambleFreeText(text) : text
        alert.addButton(withTitle: String(localized: "Übertragen"))
        alert.addButton(withTitle: String(localized: "Abbrechen"))
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Puts the expected address into one slot of a miner, after the usual confirmation.
    func applyExpectedAddress(_ address: String, slotKey: String, minerID: UUID) async throws {
        guard let miner = miners.first(where: { $0.id == minerID }) else { return }
        var form = MinerSettingsForm(miner: miner)
        let index = switch slotKey {
        case "primary": form.primarySlot
        case "fallback": form.secondarySlot
        default: Int(slotKey.dropFirst(4)) ?? -1
        }
        guard form.slots.indices.contains(index) else { return }
        form.slots[index].user = PayoutCheck.user(form.slots[index].user, withAddress: address)
        try await applyPoolSettings(form, minerID: minerID)
    }

    /// Restarts the miner. Failures are reported via the status banner.
    func restartMiner(minerID: UUID) async {
        guard let miner = miners.first(where: { $0.id == minerID }) else { return }
        do {
            try await MinerAPIClient.shared.restartMiner(host: miner.ipAddress)
        } catch {
            Log.miner.error("Restart of \(miner.ipAddress, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            showBanner(String(localized: "Neustart von \(miner.displayName) fehlgeschlagen: \(error.localizedDescription)"), isError: true)
            return
        }
        showBanner(String(localized: "Neustart für \(miner.displayName) ausgelöst."), isError: false)
        if let idx = miners.firstIndex(where: { $0.id == minerID }) {
            miners[idx].connectionState = .checking
        }
        try? await Task.sleep(for: .seconds(4))
        await refreshMiner(id: minerID)
    }

    /// A history that just started over is worth more than a few seconds of attention.
    /// Night mode, alert silence and the alert switch can change from the app or from Control Center.
    private func watchWidgetSwitches() {
        WidgetBridge.shared.attach(to: self)
        let changes: [AnyPublisher<Void, Never>] = [
            power.$manualNight.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            alerts.$silencedUntil.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            alerts.$isEnabled.dropFirst().map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(changes)
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { _ in Task { await WidgetBridge.shared.publish() } }
            .store(in: &widgetWatchers)
    }

    private func watchHistory() {
        history.onDamaged = { [weak self] in
            Task { @MainActor in self?.showHistoryDamaged() }
        }
        if history.damagedBackup != nil { showHistoryDamaged() }
    }

    private func showHistoryDamaged() {
        showBanner(String(localized: "Der Verlauf war beschädigt und beginnt neu. Die alte Datei liegt im App-Datenordner."), isError: true, seconds: 30)
    }

    func showBanner(_ message: String, isError: Bool, seconds: Int = 4) {
        statusBannerMessage = message
        statusBannerIsError = isError
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            if self?.statusBannerMessage == message {
                withAnimation {
                    self?.statusBannerMessage = nil
                }
            }
        }
    }
}
