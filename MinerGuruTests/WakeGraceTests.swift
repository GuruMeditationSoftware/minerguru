import Foundation
import Testing
@testable import MinerGuru

@Suite("Grace period after wake")
@MainActor
struct WakeGraceTests {
    @Test func noSleepNoGrace() {
        var grace = WakeGrace()
        #expect(grace.observe(wall: 0, awake: 0) == nil)
        #expect(grace.observe(wall: 5, awake: 5) == nil)
        #expect(!grace.isActive(wall: 5))
    }

    @Test func timerNoiseIsNotSleep() {
        var grace = WakeGrace()
        _ = grace.observe(wall: 0, awake: 0)
        #expect(grace.observe(wall: 10, awake: 9) == nil)
        #expect(!grace.isActive(wall: 10))
    }

    /// Like the Power Nap wakes in the real log: about five minutes asleep, the first poll fails.
    @Test func sleepStartsGraceForThirtySeconds() {
        var grace = WakeGrace()
        _ = grace.observe(wall: 0, awake: 0)
        #expect(grace.observe(wall: 300, awake: 5) == 295)
        #expect(grace.isActive(wall: 300))
        #expect(grace.isActive(wall: 329))
        #expect(!grace.isActive(wall: 330))
    }

    /// App Nap and a busy main thread slow the polls down, but both clocks keep running.
    @Test func slowPollsAreNotSleep() {
        var grace = WakeGrace()
        _ = grace.observe(wall: 0, awake: 0)
        #expect(grace.observe(wall: 600, awake: 600) == nil)
        #expect(!grace.isActive(wall: 600))
    }

    @Test func secondSleepExtendsGrace() {
        var grace = WakeGrace()
        _ = grace.observe(wall: 0, awake: 0)
        _ = grace.observe(wall: 300, awake: 5)
        #expect(grace.observe(wall: 900, awake: 25) == 580)
        #expect(grace.isActive(wall: 920))
    }

    /// The real clocks run together while the Mac is awake, so normal polls never start a grace.
    @Test func realClocksAgreeWhileAwake() async throws {
        var grace = WakeGrace()
        _ = grace.observe(wall: WakeGrace.wallSeconds, awake: WakeGrace.awakeSeconds)
        try await Task.sleep(for: .milliseconds(300))
        #expect(grace.observe(wall: WakeGrace.wallSeconds, awake: WakeGrace.awakeSeconds) == nil)
    }

    /// A miner that does not answer right after a wake keeps its state; later the same failure counts.
    @Test func storeIgnoresFailedPollRightAfterWake() async throws {
        let store = MinerStore(defaults: Fixtures.defaults(), startBackgroundWork: false)
        var clocks: (wall: TimeInterval, awake: TimeInterval) = (100, 100)
        store.wakeClocks = { clocks }
        // Nothing listens on port 1, the request fails at once.
        store.miners = [Fixtures.device(ip: "127.0.0.1:1", info: try Fixtures.bitaxeInfo())]

        await store.refreshAllMiners()
        #expect(!store.miners[0].connectionState.isOnline, "without sleep a failure counts")

        store.miners[0].connectionState = .online
        clocks = (400, 105)
        await store.refreshAllMiners()
        #expect(store.miners[0].connectionState.isOnline, "right after the wake the failure is ignored")

        clocks = (431, 136)
        await store.refreshAllMiners()
        #expect(!store.miners[0].connectionState.isOnline, "after the grace the failure counts again")
    }
}
