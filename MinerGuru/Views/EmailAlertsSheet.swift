import SwiftUI

/// Mail server, addresses and a test mail. The password goes straight to the keychain.
struct EmailAlertsSheet: View {
    @ObservedObject var email: EmailAlertSettings
    @Environment(\.dismiss) private var dismiss
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("E-Mail-Warnungen")
                .font(.headline)
            Text("MinerGuru schickt jede Warnung zusätzlich an diese Adressen, über deinen eigenen Mailserver. Das Passwort liegt im Schlüsselbund.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Form {
                Toggle("Warnungen per E-Mail senden", isOn: $email.values.isEnabled)
                TextField("Server", text: $email.values.host, prompt: Text("z. B. smtp.example.com"))
                Picker("Verschlüsselung", selection: Binding {
                    email.values.security
                } set: { security in
                    email.values.security = security
                    email.values.port = security.defaultPort
                }) {
                    ForEach(SmtpSecurity.allCases) { Text($0.title).tag($0) }
                }
                TextField("Port", value: $email.values.port, format: .number.grouping(.never))
                TextField("Benutzername", text: $email.values.username, prompt: Text("leer, wenn der Server keine Anmeldung braucht"))
                SecureField("Passwort", text: $email.password)
                TextField("Absender", text: $email.values.sender, prompt: Text("miner@example.com"))
                TextField("Empfänger", text: $email.values.recipients, prompt: Text("mehrere mit Komma trennen"))
            }
            .formStyle(.columns)
            .autocorrectionDisabled()

            if email.values.security == .none {
                Label("Ohne Verschlüsselung gehen Passwort und Inhalt lesbar durchs Netz. Nur für einen Mailserver im eigenen Netz.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Signal.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let testResult {
                Text(testResult)
                    .font(.caption)
                    .foregroundStyle(testFailed ? Signal.bad : Signal.good)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button {
                    Task { await sendTest() }
                } label: {
                    HStack(spacing: 6) {
                        if isTesting { ProgressView().controlSize(.small) }
                        Text("Test-Mail senden")
                    }
                }
                .disabled(!email.isComplete || isTesting)
                Spacer()
                Button("Fertig") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func sendTest() async {
        isTesting = true
        testResult = nil
        do {
            try await email.sendTest()
            testFailed = false
            testResult = String(localized: "Test-Mail versendet.")
        } catch {
            testFailed = true
            testResult = error.localizedDescription
        }
        isTesting = false
    }
}
