import Foundation
import Security

/// Mail settings. The password lives in the keychain, everything else in the defaults.
@MainActor
final class EmailAlertSettings: ObservableObject {
    struct Values: Codable, Equatable, Sendable {
        var isEnabled = false
        var host = ""
        var port = 587
        var security = SmtpSecurity.startTLS
        var username = ""
        var sender = ""
        /// Several addresses separated by commas.
        var recipients = ""
    }

    @Published var values: Values {
        didSet { defaults.set(try? JSONEncoder().encode(values), forKey: Self.key) }
    }
    @Published var password: String {
        didSet { Keychain.setPassword(password, account: Self.keychainAccount) }
    }

    private let defaults: UserDefaults
    private static let key = "MinerGuru.EmailAlerts.v1"
    private static let keychainAccount = "smtp"

    init(defaults: UserDefaults, readsKeychain: Bool = true) {
        self.defaults = defaults
        values = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(Values.self, from: $0) } ?? Values()
        password = readsKeychain ? (Keychain.password(account: Self.keychainAccount) ?? "") : ""
    }

    var recipientList: [String] {
        values.recipients.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == " " }).map(String.init)
    }

    var isComplete: Bool {
        !values.host.isEmpty && (1...65535).contains(values.port) && values.sender.contains("@") && !recipientList.isEmpty
    }

    private var server: SmtpServer {
        SmtpServer(host: values.host.trimmingCharacters(in: .whitespaces), port: values.port, security: values.security,
                   username: values.username, password: password)
    }

    func send(subject: String, body: String) async throws {
        try await SmtpClient.send(SmtpMessage(from: values.sender, to: recipientList, subject: subject, body: body), via: server)
    }

    func sendTest() async throws {
        try await send(subject: String(localized: "MinerGuru: Test-Mail"),
                       body: String(localized: "Diese Test-Mail zeigt: Warnungen von MinerGuru kommen bei dir an."))
    }
}

/// Sends alerts by mail on top of the normal notification. A failed mail is logged, the alert itself stays delivered.
struct EmailAlertNotifier: AlertNotifier {
    let base: AlertNotifier
    let settings: EmailAlertSettings

    func requestAuthorization() async -> Bool { await base.requestAuthorization() }

    func deliver(_ event: AlertEvent) async {
        await base.deliver(event)
        let (isReady, subject, body): (Bool, String, String) = await MainActor.run {
            (settings.values.isEnabled && settings.isComplete, "MinerGuru: \(event.title)", event.body)
        }
        guard isReady else { return }
        do {
            try await settings.send(subject: subject, body: body)
        } catch {
            Log.app.error("Warn-Mail nicht versendet: \(error.localizedDescription, privacy: .public)")
        }
    }
}

enum Keychain {
    private static let service = "app.minerguru.MinerGuru"

    static func password(account: String) -> String? {
        var result: AnyObject?
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func setPassword(_ password: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !password.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(password.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }
}
