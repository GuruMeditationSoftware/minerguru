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

            SettingsSection("Sprache", systemImage: "globe") {
                SettingsRow("Sprache der Oberfläche") {
                    Picker("Sprache der Oberfläche", selection: $language) {
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
                        Label("Die neue Sprache wird nach einem Neustart aktiv.", systemImage: "arrow.clockwise.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Jetzt neu starten") {
                            AppLanguage.relaunch()
                        }
                        .controlSize(.small)
                    }
                    .padding(.vertical, 8)
                }
            }

            SettingsSection("Aktualisierung & Überwachung", systemImage: "gauge.with.dots.needle.67percent") {
                SettingsRow("Abfrage-Intervall") {
                    Picker("Abfrage-Intervall", selection: $store.pollingIntervalSeconds) {
                        Text("Alle 2 Sekunden (Echtzeit)").tag(2)
                        Text("Alle 5 Sekunden (Empfohlen)").tag(5)
                        Text("Alle 10 Sekunden").tag(10)
                        Text("Alle 15 Sekunden").tag(15)
                        Text("Alle 30 Sekunden").tag(30)
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                Divider()

                SettingsRow("Temperatur-Warnschwelle (ASIC)") {
                    Stepper(value: $store.tempWarningThresholdC, in: 55...85, step: 1) {
                        Text("\(Int(store.tempWarningThresholdC)) °C")
                            .monospacedDigit()
                            .fontWeight(.medium)
                    }
                }
            }

            NotificationSettingsSection(alerts: store.alerts, email: store.email)

            BlockProbeSettingsSection(isEnabled: $store.stratumProbeEnabled)

            SettingsSection("Netzwerk-Scan", systemImage: "antenna.radiowaves.left.and.right") {
                SettingsRow("Standard-Subnetz (/24)") {
                    TextField("192.168.1", text: $scanner.subnetPrefix)
                        .sensitive()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                        .monospaced()
                }

                Divider()

                Toggle(isOn: $store.autoScanOnEmptyLaunch) {
                    Text("Beim Start automatisch scannen, wenn keine Miner konfiguriert sind")
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
                Link("Feedback geben", destination: AppInfo.feedbackURL)
                Button("Lizenz") { isShowingLicense = true }
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
        SettingsSection("Benachrichtigungen", systemImage: "bell.badge") {
            Toggle(isOn: $alerts.isEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bei Problemen benachrichtigen")
                    Text("Nur Alarme, keine Werbung. Läuft weiter, solange MinerGuru in der Menüleiste ist.")
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
                SettingsRow("Stummschalten") {
                    if let until = alerts.silencedUntil, alerts.isSilenced() {
                        Text("Stumm bis \(until.formatted(date: .omitted, time: .shortened))")
                            .foregroundStyle(.secondary)
                        Button("Wieder einschalten") { alerts.endSilence() }
                            .controlSize(.small)
                    } else {
                        Button("Bis morgen früh") { alerts.silenceUntilMorning() }
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
                SettingsRow("E-Mail-Warnungen") {
                    Text(email.values.isEnabled && email.isComplete ? "Aktiv" : "Aus")
                        .foregroundStyle(.secondary)
                    Button("Einrichten …") { isEditingEmail = true }
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
        SettingsSection("Soll-Adressen", systemImage: "checkmark.shield") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(coins, id: \.self) { coin in
                    let text = alerts.expectedAddresses[coin.rawValue] ?? ""
                    HStack {
                        Text(verbatim: coin.fullName)
                        Spacer()
                        TextField("Adresse", text: Binding(
                            get: { text },
                            set: { alerts.setExpectedAddress($0, for: coin) }
                        ))
                        .sensitive()
                        .textFieldStyle(.roundedBorder)
                        .monospaced()
                        .frame(maxWidth: 300)
                    }
                    if !text.isEmpty, CoinAddress.scriptPubKey(for: text) == nil {
                        Text("Das ist keine gültige Adresse.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Text("MinerGuru warnt, wenn ein Miner an eine andere Adresse zahlt, und schreibt nie von selbst eine Adresse auf einen Miner.")
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
        SettingsSection("Eingriffe", systemImage: "hand.raised") {
            Toggle("Nur lesen: nichts an Minern ändern", isOn: $isReadOnly)
                .toggleStyle(TrailingSwitch())
                .controlSize(.small)
                .padding(.vertical, 6)
            Divider()
            Toggle("Ohne Shares neu starten", isOn: $alerts.restartsOnFlatline)
                .toggleStyle(TrailingSwitch())
                .controlSize(.small)
                .padding(.vertical, 6)
                .disabled(isReadOnly)
            Divider()
            Toggle("Zum Primär-Pool zurückholen", isOn: $alerts.restartsToPrimary)
                .toggleStyle(TrailingSwitch())
                .controlSize(.small)
                .padding(.vertical, 6)
                .disabled(isReadOnly)
            Text("Automatische Neustarts höchstens einmal pro Stunde je Miner, nie bei Überhitzung. Jeder Eingriff kommt als Mitteilung und ins Protokoll.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 6)
            Divider()
            SettingsRow("Änderungsprotokoll") {
                Button("Anzeigen …") { isShowingChanges = true }
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
            Text("Änderungsprotokoll")
                .font(.headline)
            if entries.isEmpty {
                Text("Noch keine Änderungen.")
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
                Button("Exportieren …", action: export)
                    .disabled(entries.isEmpty)
                Spacer()
                Button("Schließen") { dismiss() }
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
        SettingsSection("Diagnose", systemImage: "doc.text.magnifyingglass") {
            VStack(alignment: .leading, spacing: 8) {
                SettingsRow("Diagnose-Log") {
                    Button("Exportieren …", action: export)
                }
                Text("Hält Zustände, Warnungen, Schaltvorgänge und Messwerte fest, nur auf diesem Mac. Enthält die lokalen IP-Adressen der Miner, aber keine Passwörter, Wallet-Adressen oder Codes. Wird nie automatisch gesendet.")
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
        SettingsSection("Blockansicht", systemImage: "cube") {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $isEnabled) {
                    Text("Block-Vorlage selbst beim Pool abfragen")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(TrailingSwitch())
                .controlSize(.small)
                Text("Für Miner, die ihren Block nicht selbst melden (NerdOS, AxeOS vor 2.13). MinerGuru verbindet sich dazu vom Mac aus kurz mit dem Pool des Miners, meldet sich mit dessen Adresse und dem Worker-Namen „minerguru“ an, liest den ersten Auftrag und trennt wieder. So siehst du Blockhöhe, Belohnung, Gebühren und Empfänger und ob deine Adresse dabei ist.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Es werden keine Shares eingereicht; bei 17 getesteten Solo-Pools erschien kein zusätzlicher Worker. Abgefragt wird nur bei offener Detailseite, höchstens alle 5 Minuten je Pool. Der Pool sieht die IP-Adresse deines Anschlusses, wie beim Miner auch.")
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
                    Text("Täglich nach neuen Versionen suchen")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(TrailingSwitch())
                .controlSize(.small)
                Text("MinerGuru fragt dazu GitHub nach der neuesten Version. GitHub sieht dabei deine IP-Adresse und die App-Version. Installiert wird nichts automatisch.")
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
                    Link("Zum Download", destination: AppInfo.releasesURL)
                        .font(.callout)
                }
                Button("Jetzt suchen") {
                    Task { await updates.check() }
                }
                .controlSize(.small)
                .disabled(updates.status == .checking)
            }
            .padding(.vertical, 8)
        }
    }

    private var statusText: Text {
        if updates.status == .checking { return Text("Suche läuft …") }
        if updates.status == .failed { return Text("GitHub ist gerade nicht erreichbar.") }
        if let version = updates.availableVersion { return Text("MinerGuru \(version) ist verfügbar") }
        return updates.status == .upToDate ? Text("MinerGuru ist aktuell.") : Text("Noch nicht gesucht")
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
