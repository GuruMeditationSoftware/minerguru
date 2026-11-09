import Foundation

/// Moves miners to a pool of the library at a set time on set weekdays, for example to a lottery pool on weekend
/// nights and back on Monday morning. A rule is one switch; going back is a second rule.
struct PoolScheduleRule: Codable, Sendable, Equatable, Identifiable {
    var id = UUID()
    var poolID: UUID
    /// Miners this rule switches; empty means all miners.
    var minerIDs: Set<UUID> = []
    var weekdays: Set<Weekday> = WeekdayOrder.all
    /// Minutes after midnight.
    var minute = 22 * 60
    var isEnabled = true
    /// A rule never fires for a time before it existed.
    var createdAt = Date()

    /// A miner that was offline at the set time is still switched when it comes back within this time.
    static let catchUp: TimeInterval = 30 * 60

    func applies(to minerID: UUID) -> Bool { minerIDs.isEmpty || minerIDs.contains(minerID) }

    /// The last set time at or before `date`, looking back one week at most.
    func lastOccurrence(before date: Date, calendar: Calendar = .current) -> Date? {
        for back in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: -back, to: calendar.startOfDay(for: date)),
                  weekdays.contains(calendar.component(.weekday, from: day)),
                  let moment = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day),
                  moment <= date else { continue }
            return moment
        }
        return nil
    }

    /// The occurrence that should be carried out now, if it was not carried out for this miner yet.
    func dueOccurrence(at date: Date, lastApplied: Date?, calendar: Calendar = .current) -> Date? {
        guard isEnabled, let moment = lastOccurrence(before: date, calendar: calendar),
              date.timeIntervalSince(moment) <= Self.catchUp, moment >= createdAt,
              lastApplied.map({ moment > $0 }) ?? true else { return nil }
        return moment
    }
}

extension MinerSettingsForm {
    /// Makes a library pool the miner's primary pool. AxeOS 2.15+ only moves the role if a slot already holds it.
    /// Returns `false` if the miner already mines there, so it does not need a restart.
    mutating func switchPrimary(to config: PoolConfig) -> Bool {
        if config.matches(primary) { return false }
        if poolAPI == .slots, let slot = slots.firstIndex(where: { config.matches($0) }) {
            if slot == secondarySlot { secondarySlot = primarySlot }
            primarySlot = slot
        } else {
            assign(config, toSlot: primarySlot)
        }
        return true
    }
}
