import Foundation

enum ReportPeriod: String, CaseIterable, Identifiable, Sendable {
    case yesterday, last7Days, last30Days, thisMonth, lastMonth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .yesterday: String(localized: "Yesterday")
        case .last7Days: String(localized: "Last 7 days")
        case .last30Days: String(localized: "Last 30 days")
        case .thisMonth: String(localized: "This month")
        case .lastMonth: String(localized: "Last month")
        }
    }

    func interval(now: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let month = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? today
        switch self {
        case .yesterday:
            return DateInterval(start: calendar.date(byAdding: .day, value: -1, to: today) ?? today, end: today)
        case .last7Days:
            return DateInterval(start: calendar.date(byAdding: .day, value: -7, to: today) ?? today, end: now)
        case .last30Days:
            return DateInterval(start: calendar.date(byAdding: .day, value: -30, to: today) ?? today, end: now)
        case .thisMonth:
            return DateInterval(start: month, end: now)
        case .lastMonth:
            return DateInterval(start: calendar.date(byAdding: .month, value: -1, to: month) ?? month, end: month)
        }
    }
}

/// Figures of one miner over a report period.
struct MinerReportRow: Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var uptimePercent: Double?
    var averageHashRateGHs: Double?
    var energyKWh: Double
    var cost: Double
    var efficiencyJPerTH: Double?
    var averageTempC: Double?
    var maxTempC: Double?
    var sharesAccepted: Int
    var sharesRejected: Int
    var bestDiff: Double?
}

/// Fleet report built from the hourly history: uptime, output, energy and cost per miner, plus the maintenance done.
struct MinerReport: Equatable, Sendable {
    var interval: DateInterval
    var rows: [MinerReportRow]
    /// Total fleet hashrate per day.
    var dailyHashRateGHs: [DailyValue]
    var maintenance: [MaintenanceRecord]

    struct DailyValue: Identifiable, Equatable, Sendable {
        var date: Date
        var value: Double
        var id: Date { date }
    }

    var totalEnergyKWh: Double { rows.map(\.energyKWh).reduce(0, +) }
    var totalCost: Double { rows.map(\.cost).reduce(0, +) }
    var sharesAccepted: Int { rows.map(\.sharesAccepted).reduce(0, +) }
    var sharesRejected: Int { rows.map(\.sharesRejected).reduce(0, +) }
    var bestDiff: Double? { rows.compactMap(\.bestDiff).max() }
    var maxTempC: Double? { rows.compactMap(\.maxTempC).max() }

    var uptimePercent: Double? {
        let values = rows.compactMap(\.uptimePercent)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// Sum of the miners' averages.
    var averageHashRateGHs: Double? {
        let values = rows.compactMap(\.averageHashRateGHs)
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    /// Average of the miners' efficiency, weighted by their hashrate.
    var efficiencyJPerTH: Double? {
        var watts = 0.0, terahashes = 0.0
        for row in rows {
            guard let efficiency = row.efficiencyJPerTH, let hashRate = row.averageHashRateGHs else { continue }
            watts += efficiency * hashRate / 1000
            terahashes += hashRate / 1000
        }
        return terahashes > 0 ? watts / terahashes : nil
    }

    var isEmpty: Bool { rows.isEmpty }

    /// - Parameters:
    ///   - points: Hourly history of all miners in the interval.
    ///   - minerName: Display name of a miner; deleted miners give `nil` and are listed under a short id.
    ///   - price: Energy price per kWh at a date.
    static func build(interval: DateInterval, points: [HistoryPoint], minerName: (UUID) -> String?,
                      price: (Date) -> Double, maintenance: [MaintenanceRecord],
                      calendar: Calendar = .current) -> MinerReport {
        let grouped = Dictionary(grouping: points.filter { $0.minerID != nil }) { $0.minerID! }
        let rows = grouped.map { id, points -> MinerReportRow in
            let online = points.reduce(0) { $0 + $1.onlineMinutes }
            let recorded = points.reduce(0) { $0 + $1.recordedMinutes }
            func average(_ value: (HistoryPoint) -> Double?) -> Double? {
                var sum = 0.0, weight = 0.0
                for point in points {
                    guard let v = value(point), point.onlineMinutes > 0 else { continue }
                    sum += v * Double(point.onlineMinutes)
                    weight += Double(point.onlineMinutes)
                }
                return weight > 0 ? sum / weight : nil
            }
            let energy = points.reduce(0.0) { $0 + $1.energyKWh }
            let hashRate = average(\.hashRateGHs)
            let power = average(\.powerWatts)
            return MinerReportRow(
                id: id,
                name: minerName(id) ?? String(id.uuidString.prefix(8)),
                uptimePercent: recorded > 0 ? Double(online) / Double(recorded) * 100 : nil,
                averageHashRateGHs: hashRate,
                energyKWh: energy,
                cost: points.reduce(0.0) { $0 + $1.energyKWh * price($1.date) },
                efficiencyJPerTH: hashRate.flatMap { h in power.flatMap { h > 0 ? $0 / (h / 1000) : nil } },
                averageTempC: average(\.asicTempC),
                maxTempC: points.compactMap(\.maxAsicTempC).max(),
                sharesAccepted: points.reduce(0) { $0 + $1.sharesAccepted },
                sharesRejected: points.reduce(0) { $0 + $1.sharesRejected },
                bestDiff: points.compactMap(\.bestDiff).max()
            )
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        let perDay = Dictionary(grouping: points.filter { $0.onlineMinutes > 0 }) { calendar.startOfDay(for: $0.date) }
        let daily = perDay.map { day, points -> DailyValue in
            // Average over the hours of the day, per miner, then the sum of the fleet.
            let perMiner = Dictionary(grouping: points, by: \.minerID).values.map { hours in
                hours.compactMap(\.hashRateGHs).reduce(0, +) / Double(hours.count)
            }
            return DailyValue(date: day, value: perMiner.reduce(0, +))
        }.sorted { $0.date < $1.date }

        return MinerReport(interval: interval, rows: rows, dailyHashRateGHs: daily,
                           maintenance: maintenance.filter { interval.contains($0.doneAt) }.sorted { $0.doneAt > $1.doneAt })
    }

    /// Spreadsheet export, one line per miner.
    func csvText() -> String {
        func number(_ value: Double?, _ digits: Int = 2) -> String {
            value.map { String(format: "%.\(digits)f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? ""
        }
        let header = "miner,uptime_percent,avg_hashrate_ghs,energy_kwh,cost,efficiency_j_th,avg_temp_c,max_temp_c,shares_accepted,shares_rejected,best_diff"
        let lines = rows.map { row in
            ["\"\(row.name.replacingOccurrences(of: "\"", with: "\"\""))\"", number(row.uptimePercent), number(row.averageHashRateGHs),
             number(row.energyKWh, 3), number(row.cost), number(row.efficiencyJPerTH), number(row.averageTempC), number(row.maxTempC),
             String(row.sharesAccepted), String(row.sharesRejected), number(row.bestDiff, 0)].joined(separator: ",")
        }
        return ([header] + lines).joined(separator: "\n") + "\n"
    }
}
