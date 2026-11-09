import Foundation
import Testing
@testable import MinerGuru

@Suite("Widgets and Control Center")
@MainActor
struct WidgetTests {
    @Test func commandsSurviveTheirURL() {
        let id = UUID()
        let commands: [WidgetCommand] = [.openOverview, .openMiner(id), .openPower, .nightMode(true), .nightMode(false),
                                         .silenceAlerts(true), .silenceAlerts(false)]
        for command in commands {
            #expect(WidgetCommand(url: command.url) == command)
        }
        #expect(WidgetCommand(url: URL(string: "minerguru://open/miner/kein-uuid")!) == nil)
        #expect(WidgetCommand(url: URL(string: "https://open")!) == nil)
    }

    /// A web page can open `minerguru://` links too: switches only count with the key from the snapshot.
    @Test func switchesNeedTheAppsKey() {
        let key = String(repeating: "ab", count: 32)
        let switches: [WidgetCommand] = [.nightMode(true), .nightMode(false), .silenceAlerts(true), .silenceAlerts(false)]
        for command in switches {
            #expect(WidgetCommand(url: command.url(key: key)) == command)
            #expect(WidgetCommand.accepted(command.url(key: key), key: key) == command)
            #expect(WidgetCommand.accepted(command.url, key: key) == nil)
            #expect(WidgetCommand.accepted(command.url(key: "falsch"), key: key) == nil)
            #expect(WidgetCommand.accepted(command.url(key: String(repeating: "ab", count: 31) + "ac"), key: key) == nil)
            #expect(WidgetCommand.accepted(command.url(key: ""), key: "") == nil)
        }
        // Opening commands stay free: any link may bring the window up.
        let opening: [WidgetCommand] = [.openOverview, .openPower, .openMiner(UUID())]
        for command in opening {
            #expect(command.url(key: key) == command.url)
            #expect(WidgetCommand.accepted(command.url, key: key) == command)
        }
    }

    @Test func silenceEndsAtTheNextMorning() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 23, minute: 10))!
        let early = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 5, minute: 0))!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 7))!
        #expect(AlertCenter.nextMorning(after: evening, calendar: calendar) == morning)
        #expect(AlertCenter.nextMorning(after: early, calendar: calendar) == morning)

        let alerts = AlertCenter(defaults: Fixtures.defaults(), guardsAppNap: false)
        alerts.silenceUntilMorning(now: evening, calendar: calendar)
        #expect(alerts.isSilenced(at: evening))
        #expect(!alerts.isSilenced(at: morning.addingTimeInterval(1)))
        alerts.endSilence()
        #expect(!alerts.isSilenced(at: evening))
    }

    @Test func manualNightModeWinsButKeepsAPause() {
        let store = PowerStore(defaults: Fixtures.defaults(), startBackgroundWork: false)
        let miner = UUID()
        store.runsSchedules = false
        #expect(store.wantedAction(for: miner) == nil)
        store.manualNight = true
        #expect(store.wantedAction(for: miner) == .nightMode)

        store.runsSchedules = true
        store.rules = [ScheduleRule(trigger: .window(WeeklyWindow(weekdays: WeekdayOrder.all, startMinute: 0, endMinute: 0)), action: .pause)]
        #expect(store.wantedAction(for: miner) == .pause)
        store.manualNight = false
        #expect(store.wantedAction(for: miner) == .pause)
    }
}
