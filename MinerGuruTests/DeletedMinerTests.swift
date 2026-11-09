import Foundation
import Testing
@testable import MinerGuru

/// An empty miner set means all miners, so deleting a rule's only miner must not empty it.
@Suite("Deleted miner")
@MainActor
struct DeletedMinerTests {
    private let kept = UUID()
    private let deleted = UUID()

    @Test func powerRuleKeepsItsLastMiner() {
        let store = PowerStore(defaults: Fixtures.defaults(), startBackgroundWork: false)
        let zone = UUID()
        store.rules = [
            ScheduleRule(trigger: .zone(zone), action: .pause, minerIDs: [deleted]),
            ScheduleRule(trigger: .zone(zone), action: .nightMode, minerIDs: [kept, deleted]),
            ScheduleRule(trigger: .zone(zone), action: .nightMode),
        ]
        store.forget(minerID: deleted)
        #expect(store.rules.map(\.minerIDs) == [[deleted], [kept], []])
        #expect(!store.rules[0].applies(to: kept))
    }

    @Test func poolScheduleKeepsItsLastMiner() {
        let store = PoolScheduleStore(defaults: Fixtures.defaults())
        store.rules = [
            PoolScheduleRule(poolID: UUID(), minerIDs: [deleted]),
            PoolScheduleRule(poolID: UUID(), minerIDs: [kept, deleted]),
        ]
        store.forget(minerID: deleted)
        #expect(store.rules.map(\.minerIDs) == [[deleted], [kept]])
        #expect(!store.rules[0].applies(to: kept))
    }

    @Test func maintenanceTaskKeepsItsLastMiner() {
        let store = MaintenanceStore(defaults: Fixtures.defaults())
        store.upsert(MaintenanceTask(kind: .dust, minerIDs: [deleted], intervalDays: 90, nextDue: Date()))
        store.upsert(MaintenanceTask(kind: .firmware, minerIDs: [kept, deleted], intervalDays: 30, nextDue: Date()))
        store.forget(minerID: deleted)
        #expect(Set(store.tasks.map(\.minerIDs)) == [[deleted], [kept]])
    }
}
