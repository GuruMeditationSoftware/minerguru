import Foundation
import Testing
@testable import MinerGuru

@Suite("PowerTariff")
@MainActor
struct PowerTariffTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    /// 2026-11-02 is a Monday.
    private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private let night = TariffZone(name: "Nacht", pricePerKWh: 0.24,
                                   window: WeeklyWindow(weekdays: WeekdayOrder.all, startMinute: 22 * 60, endMinute: 6 * 60))
    private let day = TariffZone(name: "Tag", pricePerKWh: 0.36,
                                 window: WeeklyWindow(weekdays: WeekdayOrder.workdays, startMinute: 6 * 60, endMinute: 22 * 60))

    private var tariff: PowerTariff {
        PowerTariff(currencyCode: "EUR", basePricePerKWh: 0.30, zones: [night, day])
    }

    @Test func windowOverMidnightBelongsToTheStartDay() {
        let friNight = WeeklyWindow(weekdays: [6], startMinute: 22 * 60, endMinute: 6 * 60)
        #expect(friNight.contains(weekday: 6, minute: 23 * 60))
        #expect(friNight.contains(weekday: 7, minute: 2 * 60))   // Saturday early morning
        #expect(!friNight.contains(weekday: 6, minute: 2 * 60))  // Friday early morning belongs to Thursday
        #expect(!friNight.contains(weekday: 7, minute: 23 * 60))
    }

    @Test func sameStartAndEndCoversTheWholeDay() {
        let weekend = WeeklyWindow(weekdays: WeekdayOrder.weekend, startMinute: 0, endMinute: 0)
        #expect(weekend.contains(weekday: 1, minute: 0))
        #expect(weekend.contains(weekday: 7, minute: 23 * 60 + 59))
        #expect(!weekend.contains(weekday: 2, minute: 12 * 60))
    }

    @Test func priceFollowsZonesAndFallsBackToBasePrice() {
        #expect(tariff.price(at: date(day: 2, hour: 12), calendar: calendar) == 0.36)  // Monday noon: day
        #expect(tariff.price(at: date(day: 3, hour: 3), calendar: calendar) == 0.24)   // Tuesday 3 am: night
        #expect(tariff.price(at: date(day: 7, hour: 12), calendar: calendar) == 0.30)  // Saturday noon: no zone
        #expect(tariff.hasGaps)
        #expect(tariff.overlappingZones.isEmpty)
    }

    @Test func firstZoneWinsOnOverlap() {
        let peak = TariffZone(name: "Spitze", pricePerKWh: 0.50,
                              window: WeeklyWindow(weekdays: WeekdayOrder.workdays, startMinute: 17 * 60, endMinute: 20 * 60))
        let withPeak = PowerTariff(currencyCode: "EUR", basePricePerKWh: 0.30, zones: [peak, night, day])
        #expect(withPeak.price(at: date(day: 2, hour: 18), calendar: calendar) == 0.50)
        #expect(withPeak.overlappingZones.count == 1)
    }

    @Test func segmentsSplitTheDayAtZoneBorders() {
        let monday = tariff.segments(weekday: 2)
        #expect(monday.map(\.zoneID) == [night.id, day.id, night.id])
        #expect(monday.first?.endMinute == 6 * 60)
        #expect(monday.last?.startMinute == 22 * 60)
        #expect(tariff.segments(weekday: 7).map(\.zoneID) == [night.id, nil, night.id])
    }

    @Test func rulesFollowTheirZoneAndFirstRuleWins() {
        let minerA = UUID(), minerB = UUID()
        let rules = [
            ScheduleRule(trigger: .zone(night.id), action: .pause, minerIDs: [minerA]),
            ScheduleRule(trigger: .zone(night.id), action: .nightMode),
        ]
        let at3am = date(day: 3, hour: 3)
        #expect(PowerSchedule.action(for: minerA, at: at3am, rules: rules, tariff: tariff, calendar: calendar) == .pause)
        #expect(PowerSchedule.action(for: minerB, at: at3am, rules: rules, tariff: tariff, calendar: calendar) == .nightMode)
        #expect(PowerSchedule.action(for: minerA, at: date(day: 3, hour: 12), rules: rules, tariff: tariff, calendar: calendar) == .normal)

        // The zone moves, the rule moves with it.
        var later = tariff
        later.zones[0].window.startMinute = 1 * 60
        later.zones[1].window.endMinute = 1 * 60
        #expect(PowerSchedule.action(for: minerB, at: date(day: 2, hour: 23), rules: rules, tariff: later, calendar: calendar) == .normal)
    }

    @Test func costUsesThePriceOfEveryQuarterHourAndSkipsPauses() {
        let miner = UUID()
        // 100 W for a whole Monday: 6 h night + 16 h day + 2 h night.
        let monday = date(day: 2, hour: 0)
        let cost = PowerSchedule.cost(watts: 100, from: monday, hours: 24, tariff: tariff, calendar: calendar)
        #expect(abs(cost - (0.8 * 0.24 + 1.6 * 0.36)) < 0.0001)

        let pauseAtNight = [ScheduleRule(trigger: .zone(night.id), action: .pause)]
        let paused = PowerSchedule.cost(watts: 100, from: monday, hours: 24, tariff: tariff,
                                        rules: pauseAtNight, minerID: miner, calendar: calendar)
        #expect(abs(paused - 1.6 * 0.36) < 0.0001)

        // Firmware without pause keeps drawing power.
        let noPause = PowerSchedule.cost(watts: 100, from: monday, hours: 24, tariff: tariff,
                                         rules: pauseAtNight, minerID: miner, canPause: false, calendar: calendar)
        #expect(abs(noPause - cost) < 0.0001)
    }

    @Test func tariffAndRulesArePersisted() {
        let defaults = Fixtures.defaults()
        let store = PowerStore(defaults: defaults, startBackgroundWork: false)
        store.tariff = tariff
        store.rules = [ScheduleRule(trigger: .zone(night.id), action: .nightMode)]
        store.runsSchedules = false

        let reloaded = PowerStore(defaults: defaults, startBackgroundWork: false)
        #expect(reloaded.tariff == tariff)
        #expect(reloaded.rules.count == 1)
        #expect(!reloaded.runsSchedules)
    }

    @Test func removingAZoneRemovesItsRules() {
        let store = PowerStore(defaults: Fixtures.defaults(), startBackgroundWork: false)
        store.tariff = tariff
        store.rules = [ScheduleRule(trigger: .zone(night.id), action: .nightMode),
                       ScheduleRule(trigger: .zone(day.id), action: .pause)]
        store.removeZone(id: night.id)
        #expect(store.tariff.zones.map(\.id) == [day.id])
        #expect(store.rules.map(\.trigger) == [.zone(day.id)])
    }
}
