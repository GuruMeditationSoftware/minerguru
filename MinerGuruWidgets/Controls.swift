import AppIntents
import AppKit
import SwiftUI
import WidgetKit

// Control Center controls (macOS 26+). They read the app's snapshot and hand switches to the app as
// `minerguru://` links: the app holds the miners' settings, the OTP sessions and the read-only mode.
// Switch links carry the key from the snapshot; without it the app ignores them (a web page could open them too).

enum AppLink {
    /// Sends a command to MinerGuru. In the background for switches; LaunchServices starts the app if needed.
    static func send(_ command: WidgetCommand) async {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = command.opensWindow
        let url = command.url(key: WidgetSnapshot.load()?.commandKey)
        _ = try? await NSWorkspace.shared.open(url, configuration: configuration)
    }

    /// Waits until the app's snapshot shows the switch, so the control does not jump back for a moment.
    static func waitForSnapshot(timeout: TimeInterval = 3, _ condition: (WidgetSnapshot) -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if let snapshot = WidgetSnapshot.load(), condition(snapshot) { return }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }
}

// MARK: - Intents

struct OpenMinerGuruIntent: AppIntent {
    static let title: LocalizedStringResource = "Open MinerGuru"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await AppLink.send(.openOverview)
        return .result()
    }
}

struct SetNightModeIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Night mode"
    static let isDiscoverable = false

    @Parameter(title: "Night mode")
    var value: Bool

    func perform() async throws -> some IntentResult {
        let on = value
        await AppLink.send(.nightMode(on))
        await AppLink.waitForSnapshot { $0.nightModeOn == on }
        return .result()
    }
}

struct SilenceAlertsIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Silence alerts"
    static let isDiscoverable = false

    @Parameter(title: "Silent")
    var value: Bool

    func perform() async throws -> some IntentResult {
        let on = value
        await AppLink.send(.silenceAlerts(on))
        await AppLink.waitForSnapshot { $0.alertsSilenced() == on }
        return .result()
    }
}

// MARK: - Values

struct ControlState: Sendable {
    var snapshot: WidgetSnapshot?

    var text: WidgetText { WidgetText(language: snapshot?.language ?? WidgetSnapshot.empty.language) }

    /// The app's snapshot, or the miners asked directly when MinerGuru has not written for a while.
    static func current() async -> ControlState {
        let entry = await SnapshotLoader.entry()
        return ControlState(snapshot: entry.snapshot, isStale: entry.source == .stale)
    }

    var isStale = false

    /// What the fleet button says under its title: a problem first, the hashrate otherwise.
    var fleetValue: String {
        guard let s = snapshot, !s.miners.isEmpty else { return text("No miners") }
        if isStale { return text("Miners not reachable") }
        if let hot = s.hotMiners.first { return "\(hot.name) · \(text.temperature(hot.tempC ?? 0))" }
        if let offline = s.offlineMiners.first { return text.format("%@ offline", offline.name) }
        return WidgetText.hashrateText(s.totalHashRateGHs)
    }

    var fleetHasProblem: Bool {
        guard let s = snapshot else { return false }
        return !s.hotMiners.isEmpty || !s.offlineMiners.isEmpty
    }

    var nightOn: Bool { snapshot?.nightModeOn ?? false }

    func nightValue(_ on: Bool) -> String {
        guard snapshot?.canSwitchMiners ?? true else { return text("Read-only") }
        let watts = (snapshot?.totalPowerW ?? 0) > 0 ? " · " + text.watts(snapshot?.totalPowerW ?? 0) : ""
        return (on ? text("On") : text("Off")) + watts
    }

    var silenced: Bool { snapshot?.alertsSilenced() ?? false }

    func alertsValue(_ silenced: Bool) -> String {
        guard snapshot?.alertsEnabled ?? false else { return text("Off") }
        if silenced, let until = snapshot?.alertsSilencedUntil {
            return text.format("Silent until %@", text.time(until))
        }
        return silenced ? text("Silent") : text("Active")
    }
}

@available(macOS 26.0, *)
struct ControlStateProvider: ControlValueProvider {
    var previewValue: ControlState { ControlState(snapshot: .preview) }

    func currentValue() async throws -> ControlState { await .current() }
}

// MARK: - Controls

@available(macOS 26.0, *)
struct FleetControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.minerguru.MinerGuru.Fleet", provider: ControlStateProvider()) { state in
            ControlWidgetButton(action: OpenMinerGuruIntent()) {
                Label {
                    Text(state.text("Fleet"))
                    Text(state.fleetValue)
                } icon: {
                    Image("minerguru.fleet")
                }
            }
            .tint(state.fleetHasProblem ? .yellow : .orange)
        }
        .displayName(LocalizedStringResource("Fleet"))
        .description(LocalizedStringResource("Fleet hashrate; opens MinerGuru."))
    }
}

@available(macOS 26.0, *)
struct NightModeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.minerguru.MinerGuru.NightMode", provider: ControlStateProvider()) { state in
            ControlWidgetToggle(isOn: state.nightOn, action: SetNightModeIntent()) {
                Text(state.text("Night mode"))
            } valueLabel: { isOn in
                Label(state.nightValue(isOn), systemImage: isOn ? "moon.fill" : "moon")
            }
            .tint(.orange)
        }
        .displayName(LocalizedStringResource("Night mode"))
        .description(LocalizedStringResource("All miners at eco clock with a quiet fan, until you switch it off again."))
    }
}

@available(macOS 26.0, *)
struct AlertsControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.minerguru.MinerGuru.Alerts", provider: ControlStateProvider()) { state in
            ControlWidgetToggle(isOn: state.silenced, action: SilenceAlertsIntent()) {
                Text(state.text("Alerts"))
            } valueLabel: { isOn in
                Label(state.alertsValue(isOn), systemImage: isOn ? "bell.slash.fill" : "bell")
            }
            .tint(.orange)
        }
        .displayName(LocalizedStringResource("Alerts"))
        .description(LocalizedStringResource("Silences alerts until tomorrow morning."))
    }
}
