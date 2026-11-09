import Foundation

/// What MinerGuru hands its widgets and Control Center controls: one JSON file, rewritten after every refresh round.
///
/// This file is compiled into the app and into the widget extension. The extension runs in a sandbox and may read
/// exactly this one folder (a read-only file exception in its entitlements). App groups would be the usual way,
/// but macOS only grants them to apps with a checked signature, and MinerGuru is signed ad hoc.
struct WidgetSnapshot: Codable, Sendable, Equatable {
    struct Miner: Codable, Sendable, Equatable, Identifiable {
        enum State: String, Codable, Sendable { case online, offline, checking }

        var id: UUID
        var name: String
        /// Board or chip line, e.g. "Gamma 601" or "4× BM1370".
        var model: String
        var host: String
        var state: State
        var hashRateGHs: Double
        var tempC: Double?
        var powerW: Double?
    }

    /// Solo odds of one coin, already formatted by the app; `coin` is its ticker symbol.
    struct Solo: Codable, Sendable, Equatable {
        var coin: String
        var odds: String
        var period: String
        var blockEvery: String
    }

    static let currentVersion = 2

    var version = currentVersion
    var date: Date
    /// UI language of the app (`de` / `en`), so the widgets speak the same language.
    var language: String
    var miners: [Miner]
    var tempWarningC: Double
    /// Fleet hashrate per hour over the last 24 hours, oldest first.
    var fleetHourlyGHs: [Double]
    /// Energy per hour of today (hours 0–23); `nil` for hours still to come.
    var energyHourlyKWh: [Double?]
    var energyPerDayKWh: Double?
    var costToday: String?
    var bestDiff: String?
    var pingMs: Double?
    /// Solo odds of every coin the fleet mines, Bitcoin first, then by hashrate; empty with no miner online.
    var solo: [Solo]
    /// The manual night mode for all miners (lower clock, quieter fan).
    var nightModeOn: Bool
    /// False in read-only mode: the app changes nothing on the miners then.
    var canSwitchMiners: Bool
    var alertsEnabled: Bool
    var alertsSilencedUntil: Date?
    /// The app's secret for switch commands (`WidgetCommand.url(key:)`). This file is only readable on this Mac, so a
    /// web page or a link elsewhere cannot switch the miners through `minerguru://`.
    var commandKey: String? = nil
}

// MARK: - Fleet figures

extension WidgetSnapshot {
    var onlineMiners: [Miner] { miners.filter { $0.state == .online } }
    var offlineMiners: [Miner] { miners.filter { $0.state == .offline } }
    var hotMiners: [Miner] { onlineMiners.filter { ($0.tempC ?? 0) >= tempWarningC } }
    var totalHashRateGHs: Double { onlineMiners.reduce(0) { $0 + $1.hashRateGHs } }
    var totalPowerW: Double { onlineMiners.reduce(0) { $0 + ($1.powerW ?? 0) } }

    var efficiencyJPerTH: Double? {
        let terahash = totalHashRateGHs / 1000
        guard terahash > 0.01, totalPowerW > 0 else { return nil }
        return totalPowerW / terahash
    }

    func alertsSilenced(at date: Date = Date()) -> Bool {
        alertsSilencedUntil.map { $0 > date } ?? false
    }
}

// MARK: - File

extension WidgetSnapshot {
    /// The app's bundle id; the extension's is the same plus `.Widgets`. The mock build has its own,
    /// so its widgets never read the real app's file.
    static var appBundleID: String {
        let id = Bundle.main.bundleIdentifier ?? "app.minerguru.MinerGuru"
        return id.hasSuffix(".Widgets") ? String(id.dropLast(".Widgets".count)) : id
    }

    /// `minerguru`, or the mock build's own scheme (both Info.plists carry it).
    static var urlScheme: String {
        Bundle.main.object(forInfoDictionaryKey: "MinerGuruURLScheme") as? String ?? "minerguru"
    }

    /// `~/Library/Application Support/app.minerguru.MinerGuru/Widgets/snapshot.json`. Built from the real home,
    /// because inside the sandbox `NSHomeDirectory()` points into the extension's container.
    static var fileURL: URL {
        realHome
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(appBundleID, isDirectory: true)
            .appendingPathComponent("Widgets", isDirectory: true)
            .appendingPathComponent("snapshot.json")
    }

    private static var realHome: URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    static func load(from url: URL = fileURL) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data),
              snapshot.version == currentVersion else { return nil }
        return snapshot
    }

    func write(to url: URL = WidgetSnapshot.fileURL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(self)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

// MARK: - Commands

/// What a widget click or a control asks the app to do, sent as a `minerguru://` URL.
/// LaunchServices hands the URL to the running app or starts it first. Any web page can open such a URL, so the
/// switches (night mode, silence) carry the snapshot's `commandKey` and the app ignores them without it.
enum WidgetCommand: Equatable, Sendable {
    case openOverview
    case openMiner(UUID)
    case openPower
    case nightMode(Bool)
    /// Silence alerts until the next morning, or end the silence.
    case silenceAlerts(Bool)

    var url: URL { url(key: nil) }

    /// The URL with the app's key for switches; opening commands go without.
    func url(key: String?) -> URL {
        let path: String
        switch self {
        case .openOverview: path = "open"
        case .openMiner(let id): path = "open/miner/\(id.uuidString)"
        case .openPower: path = "open/power"
        case .nightMode(let on): path = on ? "night/on" : "night/off"
        case .silenceAlerts(let on): path = on ? "alerts/silence" : "alerts/resume"
        }
        var components = URLComponents(string: "\(WidgetSnapshot.urlScheme)://\(path)")!
        if needsKey, let key { components.queryItems = [URLQueryItem(name: "key", value: key)] }
        return components.url!
    }

    /// Switches change the miners or the alerts; only the widgets and controls may send them.
    var needsKey: Bool { !opensWindow }

    /// The command of a URL, if the URL may give it: a switch only with the app's key.
    static func accepted(_ url: URL, key: String) -> WidgetCommand? {
        guard let command = WidgetCommand(url: url) else { return nil }
        guard command.needsKey else { return command }
        let sent = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "key" }?.value
        return sent.map { Self.same($0, key) } == true ? command : nil
    }

    /// Compares without stopping at the first difference.
    private static func same(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count, !y.isEmpty else { return false }
        return zip(x, y).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    init?(url: URL) {
        guard url.scheme == WidgetSnapshot.urlScheme, let host = url.host else { return nil }
        let parts = [host] + url.pathComponents.filter { $0 != "/" }
        switch parts {
        case ["open"]: self = .openOverview
        case ["open", "power"]: self = .openPower
        case let p where p.count == 3 && p[0] == "open" && p[1] == "miner":
            guard let id = UUID(uuidString: p[2]) else { return nil }
            self = .openMiner(id)
        case ["night", "on"]: self = .nightMode(true)
        case ["night", "off"]: self = .nightMode(false)
        case ["alerts", "silence"]: self = .silenceAlerts(true)
        case ["alerts", "resume"]: self = .silenceAlerts(false)
        default: return nil
        }
    }

    /// Opening commands bring the window up; switches work in the background.
    var opensWindow: Bool {
        switch self {
        case .openOverview, .openMiner, .openPower: return true
        case .nightMode, .silenceAlerts: return false
        }
    }
}
