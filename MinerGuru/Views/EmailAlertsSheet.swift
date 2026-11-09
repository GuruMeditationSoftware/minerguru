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
            Text("Email alerts")
                .font(.headline)
            Text("MinerGuru also sends every alert to these addresses through your own mail server. The password is kept in the keychain.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Form {
                Toggle("Send alerts by email", isOn: $email.values.isEnabled)
                TextField("Server", text: $email.values.host, prompt: Text("e.g. smtp.example.com"))
                Picker("Encryption", selection: Binding {
                    email.values.security
                } set: { security in
                    email.values.security = security
                    email.values.port = security.defaultPort
                }) {
                    ForEach(SmtpSecurity.allCases) { Text($0.title).tag($0) }
                }
                TextField("Port", value: $email.values.port, format: .number.grouping(.never))
                TextField("Username", text: $email.values.username, prompt: Text("empty if the server needs no login"))
                SecureField("Password", text: $email.password)
                TextField("Sender", text: $email.values.sender, prompt: Text("miner@example.com"))
                TextField("Recipients", text: $email.values.recipients, prompt: Text("separate several with commas"))
            }
            .formStyle(.columns)
            .autocorrectionDisabled()

            if email.values.security == .none {
                Label("Without encryption, password and content cross the network in the clear. Only for a mail server on your own network.",
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
                        Text("Send test mail")
                    }
                }
                .disabled(!email.isComplete || isTesting)
                Spacer()
                Button("Done") { dismiss() }
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
            testResult = String(localized: "Test mail sent.")
        } catch {
            testFailed = true
            testResult = error.localizedDescription
        }
        isTesting = false
    }
}
