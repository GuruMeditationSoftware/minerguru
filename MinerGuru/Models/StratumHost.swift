import Foundation

/// Normalizes pool addresses as entered in AxeOS / NerdOS (`stratum+tcp://pool.example:3333/x`).
enum StratumHost {
    private static let schemes = ["stratum+tcp://", "stratum+ssl://", "stratum://", "tcp://", "http://", "https://"]

    /// Strips scheme and path. With `keepPort: false` (default) a trailing `:port` is removed as well.
    ///
    ///     clean("stratum+tcp://eusolo.ckpool.org:3333/x")                 → "eusolo.ckpool.org"
    ///     clean("stratum+tcp://eusolo.ckpool.org:3333/x", keepPort: true) → "eusolo.ckpool.org:3333"
    static func clean(_ raw: String, keepPort: Bool = false) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let scheme = schemes.first(where: { s.lowercased().hasPrefix($0) }) {
            s = String(s.dropFirst(scheme.count))
        }
        if let slash = s.firstIndex(of: "/") {
            s = String(s[..<slash])
        }
        if !keepPort, let colon = s.firstIndex(of: ":") {
            s = String(s[..<colon])
        }
        return s
    }
}
