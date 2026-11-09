import Foundation
import Testing
@testable import MinerGuru

@Suite("Overheating and flatline")
struct MinerHealthTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func info(
        temp: Double = 55, vr: Double = 60, limit: Double? = nil, flag: Bool = false,
        shares: Int = 100, rate: Double = 1000, uptime: Int = 7200, paused: Bool = false
    ) throws -> MinerSystemInfo {
        var fields: [String: Any] = [
            "temp": temp, "vrTemp": vr, "overheat_mode": flag ? 1 : 0, "sharesAccepted": shares,
            "hashRate_1m": rate, "hashRate": rate, "uptimeSeconds": uptime, "miningPaused": paused, "poolDifficulty": 800,
        ]
        if let limit { fields["overheat_temp"] = limit }
        return try Fixtures.info(fields)
    }

    @Test func axeOSFlagAlarmsAtOnce() throws {
        var health = MinerHealth()
        health.update(try info(flag: true), at: start)
        #expect(health.isOverheating)
    }

    @Test func nerdOSNeedsThreePollsNearTheLimit() throws {
        var health = MinerHealth()
        for poll in 0..<2 { health.update(try info(temp: 72, limit: 75), at: start.addingTimeInterval(Double(poll))) }
        #expect(!health.isOverheating)
        health.update(try info(temp: 72, limit: 75), at: start.addingTimeInterval(2))
        #expect(health.isOverheating)
    }

    @Test func singleSpikeAndNormalTemperatureStayQuiet() throws {
        var health = MinerHealth()
        for temp in [72.0, 71, 60, 74, 70, 60] { health.update(try info(temp: temp, limit: 75), at: start) }
        #expect(!health.isOverheating)
    }

    @Test func voltageRegulatorCountsOnlyAboveTheLimit() throws {
        var health = MinerHealth()
        for _ in 0..<3 { health.update(try info(vr: 75, limit: 75), at: start) }
        #expect(!health.isOverheating)
        for _ in 0..<3 { health.update(try info(vr: 76, limit: 75), at: start) }
        #expect(health.isOverheating)
    }

    @Test func coolingDownNeedsThreePolls() throws {
        var health = MinerHealth()
        for _ in 0..<3 { health.update(try info(temp: 73, limit: 75), at: start) }
        for _ in 0..<2 { health.update(try info(temp: 60, limit: 75), at: start) }
        #expect(health.isOverheating)
        health.update(try info(temp: 60, limit: 75), at: start)
        #expect(!health.isOverheating)
    }

    /// Polls once a minute with the same miner state.
    private func run(_ health: inout MinerHealth, minutes: ClosedRange<Int>, _ make: (Int) throws -> MinerSystemInfo) throws {
        for minute in minutes { health.update(try make(minute), at: start.addingTimeInterval(Double(minute) * 60)) }
    }

    @Test func flatlineWhenSharesAndHashrateStand() throws {
        var health = MinerHealth()
        try run(&health, minutes: 0...9) { _ in try info() }
        #expect(!health.isFlatlining)
        try run(&health, minutes: 10...10) { _ in try info() }
        #expect(health.isFlatlining)
        #expect(health.minutesWithoutShares(at: start.addingTimeInterval(600)) == 10)
    }

    @Test func aNewShareEndsTheFlatline() throws {
        var health = MinerHealth()
        try run(&health, minutes: 0...11) { _ in try info() }
        try run(&health, minutes: 12...12) { _ in try info(shares: 101) }
        #expect(!health.isFlatlining)
    }

    @Test func movingHashrateIsNoFlatline() throws {
        var health = MinerHealth()
        try run(&health, minutes: 0...30) { try info(rate: 1000 + Double($0)) }
        #expect(!health.isFlatlining)
    }

    @Test func fastPollingStillNeedsFiveFrozenMinutes() throws {
        var health = MinerHealth()
        health.update(try info(rate: 900), at: start)
        health.update(try info(), at: start.addingTimeInterval(1000))
        for second in 1...50 { health.update(try info(), at: start.addingTimeInterval(1000 + Double(second) * 5)) }
        #expect(!health.isFlatlining)
    }

    @Test func pausedRestartingOrIdleMinersAreLeftAlone() throws {
        var paused = MinerHealth(), restarted = MinerHealth(), idle = MinerHealth()
        try run(&paused, minutes: 0...30) { _ in try info(paused: true) }
        try run(&restarted, minutes: 0...4) { try info(uptime: 60 + $0 * 60) }
        try run(&idle, minutes: 0...30) { _ in try info(rate: 0) }
        #expect(!paused.isFlatlining)
        #expect(!restarted.isFlatlining)
        #expect(!idle.isFlatlining)
    }

    @Test func poolDifficultyBeatsTheSuggestedOne() throws {
        let info = try Fixtures.info(["stratumSuggestedDifficulty": 1000, "poolDifficulty": 65536])
        #expect(info.activePoolDifficulty == 65536)
        #expect(try Fixtures.info(["stratumSuggestedDifficulty": 1000]).activePoolDifficulty == 1000)
    }

    @Test func highDifficultyWaitsForTenExpectedShares() {
        // 1 TH/s at difficulty 1 M finds a share every 4295 s.
        #expect(abs(MinerHealth.flatlineWindow(hashRateGHs: 1000, poolDifficulty: 1_000_000) - 42_950) < 1)
        #expect(MinerHealth.flatlineWindow(hashRateGHs: 1000, poolDifficulty: 800) == 600)
        #expect(MinerHealth.flatlineWindow(hashRateGHs: 1000, poolDifficulty: nil) == 600)
    }
}

@Suite("Fallback and unexpected restarts")
struct FallbackWatchTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func info(fallback: Bool = true, uptime: Int = 7200, paused: Bool = false, extra: [String: Any] = [:]) throws -> MinerSystemInfo {
        var fields: [String: Any] = [
            "isUsingFallbackStratum": fallback ? 1 : 0, "uptimeSeconds": uptime, "miningPaused": paused,
            "stratumURL": "a.example", "fallbackStratumURL": "b.example", "hashRate_1m": 1000, "hashRate": 1000,
        ]
        fields.merge(extra) { _, new in new }
        return try Fixtures.info(fields)
    }

    private func at(minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    @Test func fallbackAlarmsAfterTenMinutesInARow() throws {
        var health = MinerHealth()
        health.update(try info(), at: at(minutes: 0))
        health.update(try info(), at: at(minutes: 9))
        #expect(!health.isOnFallback)
        health.update(try info(), at: at(minutes: 10))
        #expect(health.isOnFallback)
        health.update(try info(fallback: false), at: at(minutes: 11))
        #expect(!health.isOnFallback)
    }

    @Test func aShortSwitchDoesNotCount() throws {
        var health = MinerHealth()
        health.update(try info(), at: at(minutes: 0))
        health.update(try info(fallback: false), at: at(minutes: 6))
        health.update(try info(), at: at(minutes: 7))
        health.update(try info(), at: at(minutes: 12))
        #expect(!health.isOnFallback)
    }

    @Test func startupIsForgiven() throws {
        var health = MinerHealth()
        health.update(try info(uptime: 60), at: at(minutes: 0))
        health.update(try info(uptime: 270), at: at(minutes: 4))
        health.update(try info(uptime: 310), at: at(minutes: 5))
        health.update(try info(uptime: 700), at: at(minutes: 12))
        #expect(!health.isOnFallback)
        health.update(try info(uptime: 910), at: at(minutes: 15))
        #expect(health.isOnFallback)
    }

    @Test func stuckNeedsThePrimaryPoolReachableForFifteenMinutes() throws {
        var health = MinerHealth()
        health.update(try info(), primaryReachable: false, at: at(minutes: 0))
        health.update(try info(), primaryReachable: true, at: at(minutes: 10))
        health.update(try info(), primaryReachable: true, at: at(minutes: 24))
        #expect(health.isOnFallback && !health.isStuckOnFallback)
        health.update(try info(), primaryReachable: false, at: at(minutes: 25))
        health.update(try info(), primaryReachable: true, at: at(minutes: 26))
        health.update(try info(), primaryReachable: true, at: at(minutes: 40))
        #expect(!health.isStuckOnFallback)
        health.update(try info(), primaryReachable: true, at: at(minutes: 41))
        #expect(health.isStuckOnFallback)
    }

    @Test func dualPoolMiningIsNoFallback() throws {
        var health = MinerHealth()
        let dual = try Fixtures.dualPoolInfo()
        health.update(dual, at: at(minutes: 0))
        health.update(dual, at: at(minutes: 30))
        #expect(!health.isOnFallback)
    }

    @Test func answersOutOfOrderAreNoRestart() throws {
        var health = MinerHealth()
        health.update(try info(fallback: false, uptime: 5000), at: at(minutes: 0))
        health.update(try info(fallback: false, uptime: 4999), at: at(minutes: 0))
        #expect(!health.restartedUnexpectedly)
    }

    @Test func droppingUptimeIsAnUnexpectedRestart() throws {
        var health = MinerHealth()
        health.update(try info(fallback: false, uptime: 5000), at: at(minutes: 0))
        #expect(!health.restartedUnexpectedly)
        health.update(try info(fallback: false, uptime: 20), at: at(minutes: 1))
        #expect(health.restartedUnexpectedly)
        health.update(try info(fallback: false, uptime: 80), at: at(minutes: 2))
        #expect(!health.restartedUnexpectedly)
    }

    @Test func ownRestartStaysQuiet() throws {
        var health = MinerHealth()
        health.update(try info(fallback: false, uptime: 5000), at: at(minutes: 0))
        health.update(try info(fallback: false, uptime: 20), restartExpected: true, at: at(minutes: 1))
        #expect(!health.restartedUnexpectedly)
    }

    @Test func resetReasonComesFromEitherFirmware() throws {
        #expect(try info(extra: ["resetReason": "Brownout"]).resetReason == "Brownout")
        #expect(try info(extra: ["lastResetReason": "Watchdog"]).resetReason == "Watchdog")
    }

    @Test func watchdogLimits() throws {
        var health = MinerHealth()
        #expect(health.dueAutoRestart(onFlatline: true, toPrimary: true, lastRestart: nil, at: at(minutes: 0)) == nil)
        health.update(try info(), primaryReachable: true, at: at(minutes: 0))
        health.update(try info(), primaryReachable: true, at: at(minutes: 10))
        health.update(try info(), primaryReachable: true, at: at(minutes: 15))
        #expect(health.dueAutoRestart(onFlatline: false, toPrimary: false, lastRestart: nil, at: at(minutes: 15)) == nil)
        #expect(health.dueAutoRestart(onFlatline: false, toPrimary: true, lastRestart: nil, at: at(minutes: 15)) == .stuckOnFallback)
        #expect(health.dueAutoRestart(onFlatline: false, toPrimary: true, lastRestart: at(minutes: -30), at: at(minutes: 15)) == nil)
        #expect(health.dueAutoRestart(onFlatline: false, toPrimary: true, lastRestart: at(minutes: -60), at: at(minutes: 15)) == .stuckOnFallback)
        health.update(try info(extra: ["overheat_mode": 1]), primaryReachable: true, at: at(minutes: 16))
        #expect(health.dueAutoRestart(onFlatline: true, toPrimary: true, lastRestart: nil, at: at(minutes: 16)) == nil)
    }
}
