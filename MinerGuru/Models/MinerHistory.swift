import Foundation

/// One stored time bucket of a miner: averages over the online minutes, plus sums for shares and minutes.
struct HistoryPoint: Equatable, Sendable, Identifiable {
    var minerID: UUID?
    var date: Date
    /// Minutes the miner answered, and minutes MinerGuru was watching it.
    var onlineMinutes: Int
    var recordedMinutes: Int
    var hashRateGHs: Double?
    var asicTempC: Double?
    var maxAsicTempC: Double?
    var vrTempC: Double?
    var powerWatts: Double?
    var fanPercent: Double?
    var poolLatencyMs: Double?
    var errorPercent: Double?
    var sharesAccepted: Int
    var sharesRejected: Int
    var bestDiff: Double?

    var id: String { "\(minerID?.uuidString ?? "fleet")-\(date.timeIntervalSince1970)" }

    /// J/TH; hashrate is stored in GH/s.
    var efficiencyJPerTH: Double? {
        guard let hashRateGHs, let powerWatts, hashRateGHs > 0 else { return nil }
        return powerWatts / (hashRateGHs / 1000)
    }

    var energyKWh: Double { (powerWatts ?? 0) * Double(onlineMinutes) / 60 / 1000 }

    var rejectRate: Double? {
        let total = sharesAccepted + sharesRejected
        return total > 0 ? Double(sharesRejected) / Double(total) * 100 : nil
    }
}

enum HistoryRange: String, CaseIterable, Identifiable, Sendable {
    case day, week, month, quarter, year

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .day: 86_400
        case .week: 7 * 86_400
        case .month: 30 * 86_400
        case .quarter: 90 * 86_400
        case .year: 365 * 86_400
        }
    }

    var title: String {
        switch self {
        case .day: String(localized: "24 Std.")
        case .week: String(localized: "7 Tage")
        case .month: String(localized: "30 Tage")
        case .quarter: String(localized: "90 Tage")
        case .year: String(localized: "1 Jahr")
        }
    }
}

enum HistoryMetric: String, CaseIterable, Identifiable, Sendable {
    case hashrate, temperature, efficiency, power, errors

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hashrate: String(localized: "Hashrate")
        case .temperature: String(localized: "Temperatur")
        case .efficiency: String(localized: "Effizienz")
        case .power: String(localized: "Leistung")
        case .errors: String(localized: "Fehlerquote")
        }
    }

    func value(_ point: HistoryPoint) -> Double? {
        switch self {
        case .hashrate: point.hashRateGHs
        case .temperature: point.asicTempC
        case .efficiency: point.efficiencyJPerTH
        case .power: point.powerWatts
        case .errors: point.errorPercent ?? point.rejectRate
        }
    }

    /// Runs of neighbouring points with a value, so an offline stretch stays a visible gap.
    func segments(of points: [HistoryPoint], in range: HistoryRange) -> [[HistoryPoint]] {
        let gap = TimeInterval(HistoryStore.step(span: range.seconds)) * 3
        var result: [[HistoryPoint]] = []
        for point in points where value(point) != nil {
            if let last = result.last?.last, point.date.timeIntervalSince(last.date) <= gap {
                result[result.count - 1].append(point)
            } else {
                result.append([point])
            }
        }
        return result
    }

    func format(_ value: Double) -> String {
        switch self {
        case .hashrate: MinerFormatting.formatHashrate(value)
        case .temperature: DisplayFormat.decimal(value, fractionDigits: 1) + " °C"
        case .efficiency: DisplayFormat.decimal(value, fractionDigits: 1) + " J/TH"
        case .power: DisplayFormat.decimal(value, fractionDigits: 1) + " W"
        case .errors: DisplayFormat.decimal(value, fractionDigits: 2) + " %"
        }
    }
}

enum HistoryCSV {
    private static let header = "time,miner,online_minutes,recorded_minutes,hashrate_ghs,asic_temp_c,max_asic_temp_c,vr_temp_c,power_w,efficiency_j_th,fan_percent,pool_latency_ms,error_percent,shares_accepted,shares_rejected,best_diff"

    /// Machine-readable export: ISO times, dots as decimal separator, empty fields for missing values.
    static func text(points: [HistoryPoint], minerName: (UUID?) -> String) -> String {
        let time = ISO8601DateFormatter()
        func number(_ value: Double?) -> String { value.map { String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? "" }
        func quoted(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let rows = points.map { p in
            [time.string(from: p.date), quoted(minerName(p.minerID)), String(p.onlineMinutes), String(p.recordedMinutes),
             number(p.hashRateGHs), number(p.asicTempC), number(p.maxAsicTempC), number(p.vrTempC), number(p.powerWatts),
             number(p.efficiencyJPerTH), number(p.fanPercent), number(p.poolLatencyMs), number(p.errorPercent),
             String(p.sharesAccepted), String(p.sharesRejected), number(p.bestDiff)].joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }
}
