import Foundation

// MARK: - Weekdays and times of day

/// Day of the week as `Calendar` counts it (1 = Sunday … 7 = Saturday).
typealias Weekday = Int

enum WeekdayOrder {
    /// Monday first, as the week bar and the day toggles show it.
    static let mondayFirst: [Weekday] = [2, 3, 4, 5, 6, 7, 1]
    static let all: Set<Weekday> = Set(1...7)
    static let workdays: Set<Weekday> = [2, 3, 4, 5, 6]
    static let weekend: Set<Weekday> = [1, 7]

    static func previous(_ day: Weekday) -> Weekday { day == 1 ? 7 : day - 1 }

    /// Short localized name, e.g. „Mo“.
    static func shortName(_ day: Weekday, calendar: Calendar = .current) -> String {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        return symbols[(day - 1) % symbols.count]
    }

    /// „Mo–Fr“, „Sa, So“ or „täglich“ for a set of days.
    static func summary(_ days: Set<Weekday>, calendar: Calendar = .current) -> String {
        if days == all { return String(localized: "daily") }
        if days == workdays { return "\(shortName(2, calendar: calendar))–\(shortName(6, calendar: calendar))" }
        return mondayFirst.filter(days.contains).map { shortName($0, calendar: calendar) }.joined(separator: ", ")
    }
}

/// A recurring time window: on the given days from `startMinute` to `endMinute` (minutes after midnight).
/// An end before the start runs over midnight into the next day; start == end covers the whole day.
struct WeeklyWindow: Codable, Sendable, Equatable, Hashable {
    var weekdays: Set<Weekday>
    var startMinute: Int
    var endMinute: Int

    static let minutesPerDay = 24 * 60

    var wrapsMidnight: Bool { endMinute < startMinute }
    var isWholeDay: Bool { startMinute == endMinute }

    /// Whether the window covers `minute` of a day that is `weekday`.
    func contains(weekday: Weekday, minute: Int) -> Bool {
        if isWholeDay { return weekdays.contains(weekday) }
        if wrapsMidnight {
            // The part after midnight belongs to the day the window started on.
            return (minute >= startMinute && weekdays.contains(weekday))
                || (minute < endMinute && weekdays.contains(WeekdayOrder.previous(weekday)))
        }
        return minute >= startMinute && minute < endMinute && weekdays.contains(weekday)
    }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        return contains(weekday: parts.weekday ?? 1, minute: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }

    /// „22:00–06:00“.
    var timeRangeText: String {
        isWholeDay ? String(localized: "all day") : "\(Self.clock(startMinute))–\(Self.clock(endMinute))"
    }

    static func clock(_ minute: Int) -> String {
        String(format: "%02d:%02d", (minute / 60) % 24, minute % 60)
    }
}

// MARK: - Tariff

/// One price zone of a time-of-use tariff, e.g. „Nacht“ 22–6 Uhr for 0.24 per kWh.
struct TariffZone: Codable, Sendable, Equatable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    /// Price per kWh in the tariff's currency.
    var pricePerKWh: Double
    var window: WeeklyWindow
}

/// The user's electricity tariff: a base price, optionally refined by zones.
/// The first zone that covers a moment sets its price; where no zone applies, the base price does.
struct PowerTariff: Codable, Sendable, Equatable {
    /// ISO currency code, free to choose.
    var currencyCode: String
    /// Price per kWh when no zone applies (the fixed price if there are no zones).
    var basePricePerKWh: Double
    var zones: [TariffZone]

    static let `default` = PowerTariff(
        currencyCode: Locale.current.currency?.identifier ?? "EUR",
        basePricePerKWh: 0.30,
        zones: []
    )

    var hasZones: Bool { !zones.isEmpty }

    func zone(at date: Date, calendar: Calendar = .current) -> TariffZone? {
        zones.first { $0.window.contains(date, calendar: calendar) }
    }

    func zone(weekday: Weekday, minute: Int) -> TariffZone? {
        zones.first { $0.window.contains(weekday: weekday, minute: minute) }
    }

    func price(at date: Date, calendar: Calendar = .current) -> Double {
        zone(at: date, calendar: calendar)?.pricePerKWh ?? basePricePerKWh
    }

    /// Stretches of one day with the same zone (`nil` = base price), for the week bar.
    func segments(weekday: Weekday, stepMinutes: Int = 15) -> [TariffSegment] {
        var result: [TariffSegment] = []
        for start in stride(from: 0, to: WeeklyWindow.minutesPerDay, by: stepMinutes) {
            let zoneID = zone(weekday: weekday, minute: start)?.id
            if let last = result.last, last.zoneID == zoneID {
                result[result.count - 1].endMinute = start + stepMinutes
            } else {
                result.append(TariffSegment(zoneID: zoneID, startMinute: start, endMinute: start + stepMinutes))
            }
        }
        return result
    }

    /// Pairs of zones that cover the same time somewhere in the week; the earlier one wins there.
    var overlappingZones: [(TariffZone, TariffZone)] {
        var pairs: [(TariffZone, TariffZone)] = []
        for (i, a) in zones.enumerated() {
            for b in zones[(i + 1)...] where Self.overlap(a.window, b.window) {
                pairs.append((a, b))
            }
        }
        return pairs
    }

    /// Whether some time of the week is not covered by any zone (and falls back to the base price).
    var hasGaps: Bool {
        guard hasZones else { return false }
        return WeekdayOrder.mondayFirst.contains { day in
            stride(from: 0, to: WeeklyWindow.minutesPerDay, by: 15).contains { zone(weekday: day, minute: $0) == nil }
        }
    }

    private static func overlap(_ a: WeeklyWindow, _ b: WeeklyWindow) -> Bool {
        WeekdayOrder.mondayFirst.contains { day in
            stride(from: 0, to: WeeklyWindow.minutesPerDay, by: 15).contains {
                a.contains(weekday: day, minute: $0) && b.contains(weekday: day, minute: $0)
            }
        }
    }

    func formatPrice(_ value: Double, digits: Int = 2) -> String {
        value.formatted(.currency(code: currencyCode).precision(.fractionLength(digits)))
    }
}

struct TariffSegment: Equatable, Sendable {
    var zoneID: UUID?
    var startMinute: Int
    var endMinute: Int
}

// MARK: - Schedules

/// What a schedule does with a miner while it applies.
enum PowerAction: String, Codable, Sendable, CaseIterable, Identifiable {
    /// The miner's own settings, as they were before any schedule changed them.
    case normal
    /// Lower clock and a fixed, quieter fan speed.
    case nightMode
    /// Stop hashing (AxeOS 2.15+); other firmware falls back to the night mode.
    case pause

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: return String(localized: "Normal")
        case .nightMode: return String(localized: "Night mode")
        case .pause: return String(localized: "Pause")
        }
    }

    var systemImage: String {
        switch self {
        case .normal: return "bolt"
        case .nightMode: return "moon"
        case .pause: return "pause.circle"
        }
    }
}

/// When a schedule applies: during a tariff zone (follows the zone when it changes) or a time window of its own.
enum ScheduleTrigger: Codable, Sendable, Equatable, Hashable {
    case zone(UUID)
    case window(WeeklyWindow)
}

/// Trigger + action + miners. Rules higher up in the list win when several apply at once.
struct ScheduleRule: Codable, Sendable, Equatable, Identifiable {
    var id = UUID()
    var trigger: ScheduleTrigger
    var action: PowerAction
    /// Miners this rule switches; empty means all miners.
    var minerIDs: Set<UUID> = []
    var isEnabled = true

    func applies(to minerID: UUID) -> Bool { minerIDs.isEmpty || minerIDs.contains(minerID) }

    func isActive(at date: Date, tariff: PowerTariff, calendar: Calendar = .current) -> Bool {
        guard isEnabled else { return false }
        switch trigger {
        case .zone(let id):
            return tariff.zone(at: date, calendar: calendar)?.id == id
        case .window(let window):
            return window.contains(date, calendar: calendar)
        }
    }
}

enum PowerSchedule {
    /// The action the rules ask for at `date`, `.normal` if none applies.
    static func action(for minerID: UUID, at date: Date, rules: [ScheduleRule], tariff: PowerTariff,
                       calendar: Calendar = .current) -> PowerAction {
        rules.first { $0.applies(to: minerID) && $0.isActive(at: date, tariff: tariff, calendar: calendar) }?.action ?? .normal
    }

    /// Energy cost of drawing `watts` from `start` for `hours`, at the price valid in every quarter hour.
    /// Quarter hours in which the rules pause the miner cost nothing (if its firmware can pause).
    static func cost(watts: Double, from start: Date, hours: Double, tariff: PowerTariff,
                     rules: [ScheduleRule] = [], minerID: UUID? = nil, canPause: Bool = true,
                     calendar: Calendar = .current) -> Double {
        guard watts > 0, hours > 0 else { return 0 }
        let step: TimeInterval = 15 * 60
        let steps = Int((hours * 3600 / step).rounded())
        var total = 0.0
        for i in 0..<steps {
            let moment = start.addingTimeInterval(Double(i) * step)
            if let minerID, canPause, action(for: minerID, at: moment, rules: rules, tariff: tariff, calendar: calendar) == .pause {
                continue
            }
            total += watts / 1000 * 0.25 * tariff.price(at: moment, calendar: calendar)
        }
        return total
    }
}
