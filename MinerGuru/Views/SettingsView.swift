import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Opens the settings window. Used instead of `SettingsLink`, whose `Settings` scene cannot be resized.
struct OpenSettingsButton<Label: View>: View {
    @Environment(\.openWindow) private var openWindow
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: { openWindow(id: SettingsView.windowID) }, label: label)
    }
}

struct SettingsView: View {
    static let windowID = "settings"


    @ObservedObject var store: MinerStore
    @ObservedObject private var scanner: NetworkScanStore
    @Environment(\.redactor) private var redactor
    @State private var language = AppLanguage.stored()
    @State private var isShowingLicense = false

    init(store: MinerStore) {
        self.store = store
        self._scanner = ObservedObject(wrappedValue: store.scanner)
    }

    var body: some View {
        ScrollView {
            content
        }
        .frame(minWidth: 480, idealWidth: 560, maxWidth: 800, minHeight: 360, idealHeight: 620, maxHeight: .infinity)
    }

    private var content: some View {
        VStack(spacing: 18) {
            header

            SettingsSection("Language", systemImage: "globe") {
                SettingsRow("Interface language") {
                    Picker("Interface language", selection: $language) {
                        ForEach(AppLanguage.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: language) { _, newValue in
                        AppLanguage.apply(newValue)
                    }
                }

                if AppLanguage.needsRestart(for: language) {
                    Divider()
                    HStack {
                        Label("The new language takes effect after a restart.", systemImage: "arrow.clockwise.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Restart Now") {
                            AppLanguage.relaunch()
                        }
                        .controlSize(.small)
                    }
                    .padding(.vertical, 8)
                }
            }

            SettingsSection("Refresh & Monitoring", systemImage: "gauge.with.dots.needle.67percent") {
                SettingsRow("Polling interval") {
                    Picker("Polling interval", selection: $store.pollingIntervalSeconds) {
                        Text("Every 2 seconds (real time)").tag(2)
                        Text("Every 5 seconds (recommended)").tag(5)
                        Text("Every 10 seconds").tag(10)
                        Text("Every 15 seconds").tag(15)
                        Text("Every 30 seconds").tag(30)
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                Divider()

                SettingsRow("Temperature warning threshold (ASIC)") {
                    Stepper(value: $store.tempWarningThresholdC, in: 55...85, step: 1) {
                        Text("\(Int(store.tempWarningThresholdC)) °C")
                            .monospacedDigit()
                            .fontWeight(.medium)
                    }
                }
            }

            NotificationSettingsSection(alerts: store.alerts, email: store.email)

            BlockProbeSettingsSection(isEnabled: $store.stratumProbeEnabled)

            SettingsSection("Network Scan", systemImage: "antenna.radiowaves.left.and.right") {
                SettingsRow("Default subnet (/24)") {
                    TextField("192.168.1", text: $scanner.subnetPrefix)
                        .sensitive()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                        .monospaced()
                }

                Divider()

                Toggle(isOn: $store.autoScanOnEmptyLaunch) {
                    Text("Scan automatically at launch when no miners are set up")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .toggleStyle(TrailingSwitch())
                .controlSize(.small)
                .padding(.vertical, 8)
            }

            PayoutSettingsSection(alerts: store.alerts)

            AutomationSettingsSection(alerts: store.alerts)

            UpdateSettingsSection(updates: store.updates)

            DiagnosticLogSection()

            DonationSection()

            footer
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "MinerGuru")
                    .font(.title2.weight(.medium))
                Text("Version \(Self.versionText)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(verbatim: AppInfo.madeBy)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Link("Send feedback", destination: AppInfo.feedbackURL)
                Button("License") { isShowingLicense = true }
                    .buttonStyle(.link)
            }
            .font(.callout)
        }
        .sheet(isPresented: $isShowingLicense) { LicenseSheet() }
    }

    private var footer: some View {
        let heart = Text(Image(systemName: "heart.fill")).foregroundStyle(.red)
        return Text("Made with \(heart) in Cryptospace")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }
}

/// Global switch and alert kinds. Single miners are muted on their detail page.
private struct NotificationSettingsSection: View {
    @ObservedObject var alerts: AlertCenter
    @ObservedObject var email: EmailAlertSettings
    @State private var isEditingEmail = false

    var body: some View {
        SettingsSection("Notifications", systemImage: "bell.badge") {
            Toggle(isOn: $alerts.isEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notify me about problems")
                    Text("Alerts only, no advertising. Keeps running while MinerGuru is in the menu bar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(TrailingSwitch())
            .controlSize(.small)
            .padding(.vertical, 8)

            if alerts.isEnabled {
                Divider()
                SettingsRow("Mute") {
                    if let until = alerts.silencedUntil, alerts.isSilenced() {
                        Text("Silent until \(until.formatted(date: .omitted, time: .shortened))")
                            .foregroundStyle(.secondary)
                        Button("Turn back on") { alerts.endSilence() }
                            .controlSize(.small)
                    } else {
                        Button("Until tomorrow morning") { alerts.silenceUntilMorning() }
                            .controlSize(.small)
                    }
                }
                ForEach(AlertKind.allCases) { kind in
                    Divider()
                    Toggle(kind.title, isOn: Binding(
                        get: { alerts.isKindEnabled(kind) },
                        set: { alerts.setKind(kind, enabled: $0) }
                    ))
                    .toggleStyle(TrailingSwitch())
                    .controlSize(.small)
                    .padding(.vertical, 6)
                }
                Divider()
                SettingsRow("Email alerts") {
                    Text(email.values.isEnabled && email.isComplete ? "Active" : "Off")
                        .foregroundStyle(.secondary)
                    Button("Set up …") { isEditingEmail = true }
                }
            }
        }
        .sheet(isPresented: $isEditingEmail) { EmailAlertsSheet(email: email) }
    }
}

/// The address each coin should pay to. Pool cards compare against it; nothing is written to miners from here.
private struct PayoutSettingsSection: View {
    @ObservedObject var alerts: AlertCenter
    private let coins: [MinedCoin] = [.btc, .bch, .dgb, .xec]

    var body: some View {
        SettingsSection("Expected addresses", systemImage: "checkmark.shield") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(coins, id: \.self) { coin in
                    let text = alerts.expectedAddresses[coin.rawValue] ?? ""
                    HStack {
                        Text(verbatim: coin.fullName)
                        Spacer()
                        TextField("Address", text: Binding(
                            get: { text },
                            set: { alerts.setExpectedAddress($0, for: coin) }
                        ))
                        .sensitive()
                        .textFieldStyle(.roundedBorder)
                        .monospaced()
                        .frame(maxWidth: 300)
                    }
                    if !text.isEmpty, CoinAddress.scriptPubKey(for: text) == nil {
                        Text("This is not a valid address.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Text("MinerGuru warns when a miner pays to another address and never writes an address to a miner on its own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 8)
        }
    }
}

/// What MinerGuru may do on its own, and what it did.
private struct AutomationSettingsSection: View {
    @ObservedObject var alerts: AlertCenter
    @AppStorage(ChangeLog.readOnlyKey) private var isReadOnly = false
    @State private var isShowingChanges = false

    var body: some View {
        SettingsSection("Interventions", systemImage: "hand.raised") {
            Toggle("Read-only: change nothing on miners", isOn: $isReadOnly)
                .toggleStyle(TrailingSwitch())
                .controlSize(.small)
                .padding(.vertical, 6)
            Divider()
            Toggle("Restart without shares", isOn: $alerts.restartsOnFlatline)
                .toggleStyle(TrailingSwitch())
                .controlSize(.small)
                .padding(.vertical, 6)
                .disabled(isReadOnly)
            Divider()
            Toggle("Bring back to primary pool", isOn: $alerts.restartsToPrimary)
                .toggleStyle(TrailingSwitch())
                .controlSize(.small)
                .padding(.vertical, 6)
                .disabled(isReadOnly)
            Text("Automatic restarts at most once an hour per miner, never when overheating. Every intervention sends a notification and goes into the log.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 6)
            Divider()
            SettingsRow("Change log") {
                Button("Show …") { isShowingChanges = true }
            }
        }
        .sheet(isPresented: $isShowingChanges) { ChangeLogSheet() }
    }
}

/// Every write to a miner with old and new values.
private struct ChangeLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.redactor) private var redactor
    @State private var entries = ChangeLog.shared.entries

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Change log")
                .font(.headline)
            if entries.isEmpty {
                Text("No changes yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(entries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "\(entry.date.formatted(date: .abbreviated, time: .shortened)) · \(redactor.ip(entry.host)) · \(ChangeLog.actionTitle(entry.action)) · \(entry.source.title)")
                            .font(.callout.weight(.medium))
                        ForEach(entry.fields, id: \.key) { field in
                            Text(verbatim: redactor.freeText(field.summary))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        if let failure = entry.failure {
                            Text(verbatim: failure)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            HStack {
                Button("Export …", action: export)
                    .disabled(entries.isEmpty)
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 520, height: 420)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "minerguru-changes.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ChangeLog.shared.exportText().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Log.persistence.error("Change log not savable: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Label on the left, switch at the right edge, so a column of settings lines up.
private struct TrailingSwitch: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            Toggle("", isOn: configuration.$isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

/// The local log for bug reports. It stays on the Mac until exported here.
private struct DiagnosticLogSection: View {
    var body: some View {
        SettingsSection("Diagnostics", systemImage: "doc.text.magnifyingglass") {
            VStack(alignment: .leading, spacing: 8) {
                SettingsRow("Diagnostic log") {
                    Button("Export …", action: export)
                }
                Text("Records states, alerts, switching and measurements, only on this Mac. Contains the miners' local IP addresses, but no passwords, wallet addresses or codes. Never sent automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 8)
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "minerguru-log.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DiagnosticLog.shared.exportText().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Log.persistence.error("Diagnostic log not savable: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Opt-in switch for the Stratum probe, with what it does spelled out before anyone turns it on.
private struct BlockProbeSettingsSection: View {
    @Binding var isEnabled: Bool

    var body: some View {
        SettingsSection("Block view", systemImage: "cube") {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $isEnabled) {
                    Text("Fetch the block template from the pool")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(TrailingSwitch())
                .controlSize(.small)
                Text("For miners that do not report their block themselves (NerdOS, AxeOS before 2.13). MinerGuru briefly connects from this Mac to the miner's pool, logs in with the miner's address and the worker name “minerguru”, reads the first job and disconnects. You then see block height, reward, fees and recipients, and whether your address is among them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("No shares are submitted; on 17 tested solo pools no extra worker appeared. It only asks while a miner's detail page is open, at most every 5 minutes per pool. The pool sees your connection's IP address, just as it does for your miner.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 8)
        }
    }
}

/// Titled group with an icon, drawn as a native card.
private struct UpdateSettingsSection: View {
    @ObservedObject var updates: UpdateChecker

    var body: some View {
        SettingsSection("Updates", systemImage: "arrow.down.circle") {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $updates.isEnabled) {
                    Text("Check for new versions daily")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(TrailingSwitch())
                .controlSize(.small)
                Text("MinerGuru asks GitHub for the latest version. GitHub sees your IP address and the app version. Nothing is installed automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 8)

            Divider()

            HStack {
                statusText
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                if updates.availableVersion != nil {
                    Link("Go to download", destination: AppInfo.releasesURL)
                        .font(.callout)
                }
                Button("Check now") {
                    Task { await updates.check() }
                }
                .controlSize(.small)
                .disabled(updates.status == .checking)
            }
            .padding(.vertical, 8)
        }
    }

    private var statusText: Text {
        if updates.status == .checking { return Text("Checking …") }
        if updates.status == .failed { return Text("GitHub cannot be reached right now.") }
        if let version = updates.availableVersion { return Text("MinerGuru \(version) is available") }
        return updates.status == .upToDate ? Text("MinerGuru is up to date.") : Text("Not checked yet")
    }
}

private struct SettingsSection<Content: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nativeCard()
        }
    }
}

/// Label on the left, control on the right.
private struct SettingsRow<Control: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let control: Control

    init(_ title: LocalizedStringKey, @ViewBuilder control: () -> Control) {
        self.title = title
        self.control = control()
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            control
        }
        .frame(minHeight: 28)
        .padding(.vertical, 6)
    }
}
