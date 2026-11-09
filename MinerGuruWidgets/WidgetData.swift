import Foundation
import WidgetKit

/// What every widget entry carries: the app's snapshot and where it came from.
struct FleetEntry: TimelineEntry, Sendable {
    enum Source: Equatable {
        /// Written by the running app.
        case app
        /// The app has not written for a while; the widget asked the miners itself.
        case live
        /// Neither the app nor the miners answered: old values.
        case stale
        /// No miners yet, or no snapshot at all.
        case empty
    }

    let date: Date
    let snapshot: WidgetSnapshot
    let source: Source

    var text: WidgetText { WidgetText(language: snapshot.language) }

    static let preview = FleetEntry(date: .now, snapshot: .preview, source: .app)
}

enum SnapshotLoader {
    /// After this long without a new file the app is taken for not running.
    static let appSilence: TimeInterval = 10 * 60

    static func entry(now: Date = .now) async -> FleetEntry {
        guard let snapshot = WidgetSnapshot.load(), !snapshot.miners.isEmpty else {
            return FleetEntry(date: now, snapshot: WidgetSnapshot.load() ?? .empty, source: .empty)
        }
        guard now.timeIntervalSince(snapshot.date) > appSilence else {
            return FleetEntry(date: now, snapshot: snapshot, source: .app)
        }
        let polled = await LivePoll.refresh(snapshot)
        if polled.onlineMiners.isEmpty {
            return FleetEntry(date: now, snapshot: snapshot, source: .stale)
        }
        return FleetEntry(date: now, snapshot: polled, source: .live)
    }

    /// The next look: the app reloads the widgets anyway while it runs.
    static func nextUpdate(after date: Date) -> Date {
        date.addingTimeInterval(15 * 60)
    }
}

/// Asks the miners directly (AxeOS and NerdOS answer `/api/system/info`), for when MinerGuru is not running.
/// Only the few fields a widget shows; the app keeps the full picture.
enum LivePoll {
    static func refresh(_ snapshot: WidgetSnapshot) async -> WidgetSnapshot {
        var result = snapshot
        let readings = await withTaskGroup(of: (UUID, Reading?).self) { group in
            for miner in snapshot.miners {
                group.addTask { (miner.id, await fetch(host: miner.host)) }
            }
            var collected: [UUID: Reading] = [:]
            for await (id, reading) in group {
                if let reading { collected[id] = reading }
            }
            return collected
        }
        result.miners = snapshot.miners.map { miner in
            var miner = miner
            if let reading = readings[miner.id] {
                miner.state = .online
                miner.hashRateGHs = reading.hashRateGHs
                miner.tempC = reading.tempC ?? miner.tempC
                miner.powerW = reading.powerW ?? miner.powerW
            } else {
                miner.state = .offline
                miner.hashRateGHs = 0
            }
            return miner
        }
        result.date = .now
        return result
    }

    struct Reading: Sendable {
        var hashRateGHs: Double
        var tempC: Double?
        var powerW: Double?
    }

    static func fetch(host: String) async -> Reading? {
        guard let url = URL(string: "http://\(host)/api/system/info") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rate = number(object["hashRate"]) else { return nil }
        return Reading(hashRateGHs: rate, tempC: number(object["temp"]), powerW: number(object["power"]))
    }

    /// Firmware sends numbers, sometimes as strings.
    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }
}

// MARK: - Text

/// The widgets speak the app's language, which may differ from the Mac's (set in MinerGuru's settings).
struct WidgetText {
    private let bundle: Bundle
    let locale: Locale

    init(language: String) {
        let code = language == "en" ? "en" : "de"
        bundle = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        // Figures follow the Mac's region, like in the app.
        locale = .autoupdatingCurrent
    }

    func callAsFunction(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: self(key), locale: locale, arguments: arguments)
    }

    // MARK: Figures

    /// Hashrate keeps the dot notation of the miners' own web pages, as in the app.
    static func hashrate(_ ghs: Double) -> (value: String, unit: String) {
        guard ghs > 0 else { return ("0", "GH/s") }
        if ghs >= 1000 { return (String(format: "%.2f", ghs / 1000), "TH/s") }
        return (String(format: "%.0f", ghs), "GH/s")
    }

    static func hashrateText(_ ghs: Double) -> String {
        let split = hashrate(ghs)
        return "\(split.value) \(split.unit)"
    }

    func decimal(_ value: Double, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(digits)).locale(locale))
    }

    func watts(_ value: Double) -> String { "\(decimal(value, digits: 0)) W" }
    func efficiency(_ value: Double) -> String { "\(decimal(value, digits: 1)) J/TH" }
    func temperature(_ value: Double) -> String { "\(decimal(value, digits: 0)) °C" }
    func energy(_ value: Double) -> String { "\(decimal(value, digits: 2)) kWh" }
    func milliseconds(_ value: Double) -> String { "\(decimal(value, digits: 0)) ms" }
    func time(_ date: Date) -> String { date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale)) }

    /// "225 W · 13,4 J/TH", or what is known of it.
    func powerLine(_ snapshot: WidgetSnapshot) -> String {
        var parts: [String] = []
        if snapshot.totalPowerW > 0 { parts.append(watts(snapshot.totalPowerW)) }
        if let efficiency = snapshot.efficiencyJPerTH { parts.append(self.efficiency(efficiency)) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Samples

extension WidgetSnapshot {
    static let empty = WidgetSnapshot(
        date: .now, language: Locale.preferredLanguages.first?.hasPrefix("de") == true ? "de" : "en",
        miners: [], tempWarningC: 68, fleetHourlyGHs: [], energyHourlyKWh: [], energyPerDayKWh: nil, costToday: nil,
        bestDiff: nil, pingMs: nil, solo: [], nightModeOn: false, canSwitchMiners: true, alertsEnabled: false,
        alertsSilencedUntil: nil
    )

    /// For the widget gallery and placeholders: a fleet of five like on the design boards.
    static let preview: WidgetSnapshot = {
        func miner(_ name: String, _ model: String, _ ghs: Double, _ temp: Double, _ watts: Double) -> Miner {
            Miner(id: UUID(), name: name, model: model, host: "", state: .online, hashRateGHs: ghs, tempC: temp, powerW: watts)
        }
        let day: [Double] = [16620, 16700, 16810, 16740, 16580, 16660, 16790, 16880, 16830, 16710, 16690, 16770,
                             16900, 16850, 16720, 16640, 16700, 16780, 16860, 16800, 16740, 16690, 16760, 16750]
        let hour = Calendar.current.component(.hour, from: .now)
        let german = Locale.preferredLanguages.first?.hasPrefix("de") == true
        return WidgetSnapshot(
            date: .now, language: german ? "de" : "en",
            miners: [
                miner("Bitaxe Hex", "Gamma Hex 1300", 8370, 56, 112),
                miner("NerdQAxe++", "4× BM1370", 4610, 55, 62),
                miner("Bitaxe GT", "GT 801", 2120, 56, 28),
                miner("Bitaxe Gamma", "Gamma 601", 1030, 56, 15),
                miner("Bitaxe Supra", "Supra 401", 615, 54, 8),
            ],
            tempWarningC: 68, fleetHourlyGHs: day,
            energyHourlyKWh: (0..<24).map { $0 <= hour ? 0.225 : nil },
            energyPerDayKWh: 5.4, costToday: german ? "1,62 €" : "€1.62", bestDiff: "886M", pingMs: 33,
            solo: [
                Solo(coin: "BTC", odds: german ? "1 : 829.876" : "1 : 829,876", period: german ? "Pro Tag" : "Per day",
                     blockEvery: german ? "~2.272 J." : "~2,272 yrs"),
                Solo(coin: "BCH", odds: german ? "1 : 4.412" : "1 : 4,412", period: german ? "Pro Tag" : "Per day",
                     blockEvery: german ? "~12 J." : "~12 yrs"),
            ],
            nightModeOn: false, canSwitchMiners: true, alertsEnabled: true, alertsSilencedUntil: nil
        )
    }()
}
