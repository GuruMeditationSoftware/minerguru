import SwiftUI

/// Screenshot-safe mode: IP and MAC addresses, wallet addresses and the WLAN name are replaced by
/// scrambled characters of the same kind (digit → digit, letter → letter), so the layout stays the
/// same but nothing real is visible. Text fields and raw data are blurred instead.
enum PrivacyMode {
    static let storageKey = "MinerGuru.HideSensitiveData.v1"

    private static let digits = Array("0123456789")
    private static let lowercase = Array("abcdefghijklmnopqrstuvwxyz")
    private static let uppercase = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    private static let hexLower = Array("0123456789abcdef")
    private static let hexUpper = Array("0123456789ABCDEF")

    /// Replaces every digit and letter by a pseudo-random one of the same kind; other characters stay.
    /// The same input always gives the same output (no flicker), across app launches.
    /// With `hex`, letters stay hexadecimal (`0-9a-f`), e.g. for MAC addresses.
    static func scramble(_ text: String, hex: Bool = false) -> String {
        // FNV-1a: stable across launches, unlike `hashValue`
        var state: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            state ^= UInt64(byte)
            state = state &* 0x100000001b3
        }
        func pick(_ alphabet: [Character]) -> Character {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return alphabet[Int((state >> 33) % UInt64(alphabet.count))]
        }
        return String(text.map { char -> Character in
            if char.isASCII, char.isNumber { return pick(hex ? hexLower : digits) }
            if char.isASCII, char.isLowercase { return pick(hex ? hexLower : lowercase) }
            if char.isASCII, char.isUppercase { return pick(hex ? hexUpper : uppercase) }
            return char
        })
    }

    /// Stratum user `wallet.worker`: only the wallet part is scrambled, the worker name stays readable.
    static func scrambleStratumUser(_ user: String) -> String {
        guard let dot = user.firstIndex(of: ".") else { return scramble(user) }
        return scramble(String(user[..<dot])) + String(user[dot...])
    }

    private static let freeTextPatterns: [(regex: NSRegularExpression, hex: Bool)] = [
        (#"\b(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b"#, true),  // MAC address
        (#"\b(?:\d{1,3}\.){3}\d{1,3}\b"#, false),                 // IPv4 address
        (#"\b[A-Za-z0-9]{25,}\b"#, false),                         // wallet address / long token
    ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

    /// Scrambles IP and MAC addresses and wallet-like tokens inside free text such as log lines.
    static func scrambleFreeText(_ text: String) -> String {
        var result = text
        for (regex, hex) in freeTextPatterns {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                result.replaceSubrange(range, with: scramble(String(result[range]), hex: hex))
            }
        }
        return result
    }
}

/// Formats sensitive values for display, depending on whether the privacy mode is on.
/// Views read it from the environment, so they update as soon as the mode is toggled.
struct Redactor: Equatable {
    var isActive = false

    func ip(_ value: String) -> String { isActive ? PrivacyMode.scramble(value) : value }
    func stratumUser(_ value: String) -> String { isActive ? PrivacyMode.scrambleStratumUser(value) : value }
    func address(_ value: String) -> String { isActive ? PrivacyMode.scramble(value) : value }
    func mac(_ value: String) -> String { isActive ? PrivacyMode.scramble(value, hex: true) : value }
    func ssid(_ value: String) -> String { isActive ? PrivacyMode.scramble(value) : value }
    func freeText(_ value: String) -> String { isActive ? PrivacyMode.scrambleFreeText(value) : value }
}

extension EnvironmentValues {
    @Entry var redactor = Redactor()
}

private struct SensitiveBlurModifier: ViewModifier {
    @Environment(\.redactor) private var redactor

    func body(content: Content) -> some View {
        content
            .blur(radius: redactor.isActive ? 6 : 0, opaque: false)
            .accessibilityHidden(redactor.isActive)
            .animation(.easeInOut(duration: 0.15), value: redactor.isActive)
    }
}

extension View {
    /// For input fields and raw data whose content cannot be replaced: blurred in privacy mode.
    func sensitive() -> some View {
        modifier(SensitiveBlurModifier())
    }
}

/// Toolbar button that toggles the privacy mode (eye).
struct PrivacyToggleButton: View {
    @AppStorage(PrivacyMode.storageKey) private var hidden = false

    var body: some View {
        Button {
            hidden.toggle()
        } label: {
            Label(hidden ? "Sensible Daten einblenden" : "Sensible Daten ausblenden", systemImage: hidden ? "eye.slash.fill" : "eye")
        }
        .help(hidden
              ? "IP-, Wallet- und MAC-Adressen wieder anzeigen (⇧⌘H)"
              : "IP-, Wallet- und MAC-Adressen für Screenshots verschleiern (⇧⌘H)")
    }
}
