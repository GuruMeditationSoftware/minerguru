import AppKit
import Foundation
import WidgetKit

/// Keeps the widgets and Control Center controls in step with the app: writes `WidgetSnapshot` after every
/// refresh round and carries out the `minerguru://` commands that widget clicks and controls send.
@MainActor
final class WidgetBridge {
    static let shared = WidgetBridge()

    /// Set by the menu bar label, which always lives and can open SwiftUI windows.
    var openMainWindow: (() -> Void)?

    private weak var store: MinerStore?
    private var lastWritten: WidgetSnapshot?
    private var lastWidgetReload: Date?
    private var hourly: (at: Date, fleet: [Double], energy: [Double?])?
    /// Commands that arrived before the store was ready (the URL that launched the app).
    private var pending: [WidgetCommand] = []

    /// Secret for switch commands, made once and kept: the controls read it from the snapshot, a web page cannot.
    let commandKey: String = {
        let defaultsKey = "widgetCommandKey"
        if let saved = UserDefaults.standard.string(forKey: defaultsKey), saved.count >= 32 { return saved }
        var generator = SystemRandomNumberGenerator()
        let key = (0..<4).map { _ in String(format: "%016llx", generator.next() as UInt64) }.joined()
        UserDefaults.standard.set(key, forKey: defaultsKey)
        return key
    }()

    /// Widgets and controls follow drifting figures (hashrate, power) this often; state changes reload them at once.
    /// Faster would run into WidgetKit's reload budget.
    static let widgetReloadInterval: TimeInterval = 60
    /// The 24-hour charts change slowly; the history database is asked this often.
    static let hourlyInterval: TimeInterval = 10 * 60

    func attach(to store: MinerStore) {
        self.store = store
        let waiting = pending
        pending = []
        for command in waiting { handle(command) }
    }

    // MARK: - Snapshot

    /// Writes the snapshot and reloads widgets and controls where something visible changed.
    func publish(now: Date = Date()) async {
        guard let store else { return }
        if hourly.map({ now.timeIntervalSince($0.at) >= Self.hourlyInterval }) ?? true {
            let points = await store.history.hourlyPoints(from: now.addingTimeInterval(-24 * 3600), to: now)
            hourly = (now, Self.fleetHourly(points, now: now), Self.energyHourly(points, now: now))
        }
        let snapshot = makeSnapshot(store: store, now: now)
        do {
            try snapshot.write()
        } catch {
            Log.app.error("Widget snapshot not written: \(error.localizedDescription, privacy: .public)")
            return
        }
        let previous = lastWritten
        lastWritten = snapshot

        let controlsChanged = previous.map { Self.controlState($0) != Self.controlState(snapshot) } ?? true
        let widgetsChanged = previous.map { Self.widgetState($0) != Self.widgetState(snapshot) } ?? true
        let due = lastWidgetReload.map { now.timeIntervalSince($0) >= Self.widgetReloadInterval } ?? true
        if widgetsChanged || controlsChanged || due {
            lastWidgetReload = now
            WidgetCenter.shared.reloadAllTimelines()
            reloadControls()
        }
    }

    private func makeSnapshot(store: MinerStore, now: Date) -> WidgetSnapshot {
        let miners = store.miners.map { miner -> WidgetSnapshot.Miner in
            let state: WidgetSnapshot.Miner.State
            switch miner.connectionState {
            case .online: state = .online
            case .offline: state = .offline
            case .checking, .unknown: state = .checking
            }
            let info = miner.latestInfo
            return WidgetSnapshot.Miner(
                id: miner.id, name: miner.displayName, model: miner.hardwareTitle, host: miner.ipAddress, state: state,
                hashRateGHs: state == .online ? info?.hashRate ?? 0 : 0,
                tempC: info?.temp, powerW: info?.power
            )
        }
        let solo = store.activeFleetCoinSummaries.filter { $0.totalHashrateGHs > 0 }.map { summary in
            WidgetSnapshot.Solo(
                coin: summary.coin.symbol.uppercased(),
                odds: summary.formattedOddsRatio(for: store.soloChanceTimeframe),
                period: store.soloChanceTimeframe.title,
                blockEvery: summary.expectedTimePerBlockFormatted
            )
        }
        let online = store.onlineMiners
        let cost = online.reduce(0) { $0 + store.power.costToday(for: $1) }
        return WidgetSnapshot(
            date: now,
            language: AppLanguage.launchCode ?? "de",
            miners: miners,
            tempWarningC: store.tempWarningThresholdC,
            fleetHourlyGHs: hourly?.fleet ?? [],
            energyHourlyKWh: hourly?.energy ?? [],
            energyPerDayKWh: online.isEmpty ? nil : store.totalPowerWatts * 24 / 1000,
            costToday: online.isEmpty || cost <= 0 ? nil : store.power.tariff.formatPrice(cost),
            bestDiff: online.isEmpty ? nil : store.highestBestDiffFormatted,
            pingMs: store.averagePoolLatencyMs,
            solo: online.isEmpty ? [] : solo,
            nightModeOn: store.power.manualNight,
            canSwitchMiners: !ChangeLog.isReadOnly,
            alertsEnabled: store.alerts.isEnabled,
            alertsSilencedUntil: store.alerts.isSilenced(at: now) ? store.alerts.silencedUntil : nil,
            commandKey: commandKey
        )
    }

    /// Sum of the miners' hourly averages, weighted by the share of the hour they were online.
    static func fleetHourly(_ points: [HistoryPoint], now: Date) -> [Double] {
        var byHour: [Date: Double] = [:]
        for point in points {
            guard let rate = point.hashRateGHs, point.recordedMinutes > 0 else { continue }
            byHour[point.date, default: 0] += rate * Double(point.onlineMinutes) / Double(point.recordedMinutes)
        }
        return byHour.keys.sorted().suffix(24).map { byHour[$0] ?? 0 }
    }

    /// kWh per hour of today; hours still to come stay `nil`.
    static func energyHourly(_ points: [HistoryPoint], now: Date, calendar: Calendar = .current) -> [Double?] {
        let start = calendar.startOfDay(for: now)
        var hours = [Double?](repeating: nil, count: 24)
        let currentHour = calendar.component(.hour, from: now)
        for hour in 0...currentHour { hours[hour] = 0 }
        for point in points where point.date >= start {
            guard let watts = point.powerWatts else { continue }
            let hour = calendar.component(.hour, from: point.date)
            hours[hour] = (hours[hour] ?? 0) + watts * Double(point.onlineMinutes) / 60 / 1000
        }
        return hours
    }

    /// What the controls show: a change here reloads them at once.
    private static func controlState(_ s: WidgetSnapshot) -> [String] {
        ["\(s.onlineMiners.count)/\(s.miners.count)",
         "\(s.hotMiners.map(\.id))", "\(s.nightModeOn)", "\(s.canSwitchMiners)", "\(s.alertsEnabled)",
         "\(s.alertsSilencedUntil?.timeIntervalSince1970 ?? 0)"]
    }

    /// States the widgets show with a shape or a line of their own.
    private static func widgetState(_ s: WidgetSnapshot) -> [String] {
        s.miners.map { "\($0.id)-\($0.state.rawValue)" } + ["\(s.hotMiners.map(\.id))", s.language]
    }

    private func reloadControls() {
        if #available(macOS 26.0, *) {
            ControlCenter.shared.reloadAllControls()
        }
    }

    // MARK: - Commands

    func handle(url: URL) {
        guard let command = WidgetCommand.accepted(url, key: commandKey) else {
            if WidgetCommand(url: url) != nil {
                DiagnosticLog.shared.write("widget", "command \(url.host ?? "")\(url.path) ignored: no valid key")
            }
            return
        }
        DiagnosticLog.shared.write("widget", "command \(url.host ?? "")\(url.path)")
        handle(command)
    }

    func handle(_ command: WidgetCommand) {
        guard let store else {
            pending.append(command)
            return
        }
        switch command {
        case .openOverview:
            store.selection = .overview
        case .openMiner(let id):
            store.selection = store.miners.contains { $0.id == id } ? .miner(id) : .overview
        case .openPower:
            store.selection = .power
        case .nightMode(let on):
            store.power.manualNight = on
        case .silenceAlerts(let on):
            if on { store.alerts.silenceUntilMorning() } else { store.alerts.endSilence() }
        }
        if command.opensWindow {
            openMainWindow?()
        }
        Task { await publish() }
    }
}
