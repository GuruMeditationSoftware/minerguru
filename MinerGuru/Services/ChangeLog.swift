import Foundation

/// Who caused a write to a miner.
enum ChangeSource: String, Codable, Sendable {
    case manual, schedule, watchdog

    var title: String {
        switch self {
        case .manual: String(localized: "Von Hand")
        case .schedule: String(localized: "Zeitplan")
        case .watchdog: String(localized: "Automatik")
        }
    }
}

/// One value a write changes. `before` is `nil` where the miner does not report the field.
struct ChangeField: Codable, Equatable, Sendable {
    let key: String
    let before: String?
    let after: String

    var title: String { ChangeLog.title(forKey: key) }
    /// The line a person reads, in the confirmation and the change log.
    var summary: String { "\(title): \(before.map { ChangeLog.shown($0, forKey: key) } ?? "–") → \(ChangeLog.shown(after, forKey: key))" }
}

struct ChangeEntry: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    let date: Date
    let host: String
    let action: String
    let fields: [ChangeField]
    let source: ChangeSource
    /// `nil` when the miner accepted the write, otherwise the reason it failed.
    let failure: String?
}

/// What MinerGuru changed on miners, and the optional read-only mode. `MinerAPIClient` is the only
/// place that writes to a miner, so everything lands here, automatic actions included.
final class ChangeLog: @unchecked Sendable {
    static let shared = ChangeLog()
    static let maxEntries = 500
    static let readOnlyKey = "MinerGuru.ReadOnly.v1"
    /// Raised around a rule's or the watchdog's writes.
    @TaskLocal static var source = ChangeSource.manual

    private let lock = NSLock()
    private var path: URL?
    private var loaded: [ChangeEntry] = []
    private var values: [String: [String: String]] = [:]

    func activate(path: URL = ChangeLog.defaultPath) {
        lock.withLock {
            self.path = path
            if let data = try? Data(contentsOf: path), let stored = try? Self.decoder.decode([ChangeEntry].self, from: data) {
                loaded = stored
            }
        }
    }

    static var defaultPath: URL {
        DiagnosticLog.defaultPath.deletingLastPathComponent().appendingPathComponent("changes.json")
    }

    static var isReadOnly: Bool { UserDefaults.standard.bool(forKey: readOnlyKey) }

    /// Newest first.
    var entries: [ChangeEntry] { lock.withLock { loaded.reversed() } }

    /// Remembers what a miner reports, to show the value a later write replaces.
    func noteValues(host: String, rawJSON: String?) {
        guard let rawJSON, let current = Self.flatten(rawJSON: rawJSON) else { return }
        lock.withLock { values[host] = current }
    }

    func values(host: String) -> [String: String] { lock.withLock { values[host] ?? [:] } }

    func record(_ entry: ChangeEntry) {
        lock.withLock {
            loaded.append(entry)
            if loaded.count > Self.maxEntries { loaded.removeFirst(loaded.count - Self.maxEntries) }
            guard let path, let data = try? Self.encoder.encode(loaded) else { return }
            try? data.write(to: path, options: .atomic)
        }
    }

    /// Records a write that went to the miner. Session requests for one-time codes change nothing.
    func recordWrite(host: String, method: String, path: String, body: Data?, failure: String?, at date: Date = Date()) {
        guard !path.contains("/otp/") else { return }
        let fields = body.map { Self.changes(body: $0, current: values(host: host)) } ?? []
        record(ChangeEntry(date: date, host: host, action: Self.action(method: method, path: path), fields: fields, source: Self.source, failure: failure))
    }

    func clear() {
        lock.withLock {
            loaded = []
            if let path { try? FileManager.default.removeItem(at: path) }
        }
    }

    /// When MinerGuru last wrote to `host` at all.
    func lastWrite(host: String) -> Date? {
        lock.withLock { loaded.last { $0.host == host }?.date }
    }

    func lastRestart(host: String) -> Date? {
        lock.withLock { loaded.last { $0.host == host && $0.action == "restart" }?.date }
    }

    /// The watchdog's last attempt on `host`, successful or not.
    func lastAutomaticRestart(host: String) -> Date? {
        lock.withLock { loaded.last { $0.host == host && $0.action == "restart" && $0.source == .watchdog }?.date }
    }

    func exportText() -> String {
        let formatter = ISO8601DateFormatter()
        return entries.reversed().map { entry in
            let changes = entry.fields.map { "\($0.key): \($0.before ?? "-") -> \($0.after)" }.joined(separator: "; ")
            return "\(formatter.string(from: entry.date)) \(entry.host) \(entry.source.rawValue) \(entry.action) \(entry.failure.map { "failed: \($0)" } ?? "ok") \(changes)\n"
        }.joined()
    }

    // MARK: - Values

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// `restart`, `pause`, `resume`, `settings` or `clearSlot`.
    static func action(method: String, path: String) -> String {
        if method == "DELETE" { return "clearSlot" }
        for name in ["restart", "pause", "resume"] where path.hasSuffix(name) { return name }
        return "settings"
    }

    static func actionTitle(_ action: String) -> String {
        switch action {
        case "restart": String(localized: "Neustart")
        case "pause": String(localized: "Pausieren")
        case "resume": String(localized: "Fortsetzen")
        case "clearSlot": String(localized: "Pool-Slot geleert")
        default: String(localized: "Einstellungen")
        }
    }

    static func flatten(rawJSON: String) -> [String: String]? {
        guard let data = rawJSON.data(using: .utf8), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return flatten(object)
    }

    /// Top-level values, and pool slots as `pools.<id>.<field>`, for comparing. Only `changes` leaves this class.
    static func flatten(_ object: [String: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in object {
            if key == "pools", let pools = value as? [[String: Any]] {
                for (index, pool) in pools.enumerated() {
                    let id = (pool["id"] as? Int) ?? index
                    for (field, item) in pool {
                        if field != "id", let text = comparable(field, item) { result["pools.\(id).\(field)"] = text }
                    }
                }
            } else if let text = comparable(key, value) {
                result[key] = text
            }
        }
        return result
    }

    /// The fields of a write whose value differs from what the miner reports.
    static func changes(body: Data, current: [String: String]) -> [ChangeField] {
        guard let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return [] }
        return flatten(object).sorted { $0.key < $1.key }.compactMap { key, after in
            if current[key] == after { return nil }
            return isSecret(key)
                ? ChangeField(key: key, before: nil, after: secretMask)
                : ChangeField(key: key, before: current[key], after: after)
        }
    }

    private static let secretMask = "•••"

    private static func isSecret(_ key: String) -> Bool {
        let key = key.lowercased()
        return key.contains("pass") || key.contains("token") || key.contains("cert") || key.contains("otp")
    }

    /// The firmware's mask for a stored password means "keep it", so that is no change.
    private static func comparable(_ key: String, _ value: Any) -> String? {
        guard let text = text(value) else { return nil }
        return isSecret(key) && (text == AxeOSPool.maskedPassword || text.isEmpty) ? nil : text
    }

    private static func text(_ value: Any) -> String? {
        switch value {
        case let text as String: text
        case let number as NSNumber: number.stringValue
        default: nil
        }
    }

    /// A short name for a field; unknown fields keep the name the miner uses.
    static func title(forKey key: String) -> String {
        var name = key
        var prefix = ""
        if key.hasPrefix("pools."), case let parts = key.split(separator: "."), parts.count == 3 {
            name = String(parts[2])
            prefix = "Pool \((Int(parts[1]) ?? 0) + 1): "
        }
        let title: String
        switch name {
        case "hostname": title = String(localized: "Hostname")
        case "frequency": title = String(localized: "Frequenz")
        case "coreVoltage": title = String(localized: "Kernspannung")
        case "autofanspeed": title = String(localized: "Lüfterautomatik")
        case "fanspeed", "manualFanSpeed": title = String(localized: "Lüfter")
        case "stratumURL": title = String(localized: "Pool-Adresse")
        case "stratumPort": title = String(localized: "Pool-Port")
        case "stratumUser": title = String(localized: "Pool-Benutzer")
        case "stratumPassword": title = String(localized: "Pool-Passwort")
        case "fallbackStratumURL": title = String(localized: "Fallback-Adresse")
        case "fallbackStratumPort": title = String(localized: "Fallback-Port")
        case "fallbackStratumUser": title = String(localized: "Fallback-Benutzer")
        case "fallbackStratumPassword": title = String(localized: "Fallback-Passwort")
        case "overclockEnabled": title = String(localized: "Eigene Taktwerte")
        case "temptarget", "pidTargetTemp": title = String(localized: "Zieltemperatur")
        case "poolMode": title = String(localized: "Pool-Modus")
        case "poolBalance": title = String(localized: "Pool-Aufteilung")
        case "primaryPoolIndex": title = String(localized: "Primärer Pool-Platz")
        case "secondaryPoolIndex": title = String(localized: "Fallback-Platz")
        case "id": title = String(localized: "Platz")
        case "stratumProtocol": title = String(localized: "Protokoll")
        case "stratumTLS": title = "TLS"
        case "stratumSuggestedDifficulty": title = String(localized: "Vorgeschlagene Difficulty")
        case "stratumExtranonceSubscribe": title = "Extranonce-Subscribe"
        case "stratumDecodeCoinbase": title = String(localized: "Coinbase auswerten")
        case "stratumShareWarning": title = String(localized: "Share-Warnung")
        case "stratumV2ChannelType": title = String(localized: "SV2-Kanaltyp")
        case "stratumV2AuthorityPubkey": title = String(localized: "SV2-Authority-Key")
        case "stratumV2RequireAuth": title = String(localized: "SV2-Authentifizierung")
        default: title = name
        }
        return prefix + title
    }

    /// Values the firmware stores as numbers, in words. Everything else stays as it is.
    static func shown(_ value: String, forKey key: String) -> String {
        let name = key.split(separator: ".").last.map(String.init) ?? key
        switch name {
        case "overclockEnabled", "autofanspeed", "stratumExtranonceSubscribe", "stratumDecodeCoinbase", "stratumShareWarning", "stratumV2RequireAuth":
            if value == "1" || value == "true" { return String(localized: "an") }
            if value == "0" || value == "false" { return String(localized: "aus") }
        case "poolMode":
            if value == "0" { return "Failover" }
            if value == "1" { return "Dual-Pool" }
        case "poolBalance":
            return "\(value) %"
        case "primaryPoolIndex", "secondaryPoolIndex":
            if let index = Int(value) { return "\(index + 1)" }
        default: break
        }
        return value
    }
}
