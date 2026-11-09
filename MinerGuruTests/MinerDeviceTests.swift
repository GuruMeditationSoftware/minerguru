import Foundation
import Testing
@testable import MinerGuru

@Suite("MinerDevice")
struct MinerDeviceTests {
    @Test func displayNamePrefersCustomNameThenHostnameThenIP() throws {
        var device = Fixtures.device(ip: "192.168.1.28")
        #expect(device.displayName == "192.168.1.28")
        device.cachedHostname = "cached"
        #expect(device.displayName == "cached")
        device.latestInfo = try Fixtures.bitaxeInfo()
        #expect(device.displayName == "bitaxe")
        device.customName = "  Wohnzimmer "
        #expect(device.displayName == "Wohnzimmer")
        device.customName = "   "
        #expect(device.displayName == "bitaxe")
    }

    @Test func hardwareTitleAndFirmwareDetection() throws {
        var device = Fixtures.device()
        #expect(device.hardwareTitle == "Unbekannter Miner")
        device.cachedHardwareModel = "Bitaxe Gamma 601"
        #expect(device.hardwareTitle == "Bitaxe Gamma 601")
        #expect(!device.isNerdOS)
        device.latestInfo = try Fixtures.dualPoolInfo()
        #expect(device.isNerdOS)
        #expect(device.isMultiChip)
    }

    @Test func persistedConfigUsesLatestTelemetry() throws {
        let device = Fixtures.device(ip: "10.0.0.5", name: "Keller", info: try Fixtures.bitaxeInfo())
        let config = device.persistedConfig
        #expect(config.id == device.id)
        #expect(config.ipAddress == "10.0.0.5")
        #expect(config.customName == "Keller")
        #expect(config.cachedHostname == "bitaxe")
        #expect(config.cachedHardwareModel == "Bitaxe Gamma 601")

        let decoded = try JSONDecoder().decode(PersistedMinerConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded == config)
    }

    @Test func singlePoolLatencyPrefersMeasurement() throws {
        let info = try Fixtures.bitaxeInfo(overrides: ["responseTime": 0])
        let device = Fixtures.device(info: info, latency: PoolLatencyMeasurement(primaryPoolDirectMs: 31, fallbackPoolDirectMs: 44))
        #expect(device.activePoolLatencyMs == 31)

        let fallback = Fixtures.device(info: try Fixtures.bitaxeInfo(overrides: ["responseTime": 0, "isUsingFallbackStratum": 1]),
                                       latency: PoolLatencyMeasurement(primaryPoolDirectMs: 31, fallbackPoolDirectMs: 44))
        #expect(fallback.activePoolLatencyMs == 44)
    }

    @Test func dualPoolLatencyIsWeightedByHashrateSplit() throws {
        let device = Fixtures.device(info: try Fixtures.dualPoolInfo())
        #expect(device.primaryPoolEffectiveLatencyMs == 20)
        #expect(device.secondaryPoolEffectiveLatencyMs == 30)
        let weighted = try #require(device.activePoolLatencyMs)
        #expect(abs(weighted - (20 * 0.01 + 30 * 0.99)) < 1e-9)
    }

    @Test func effectiveLatencyMeasurement() {
        #expect(PoolLatencyMeasurement(minerReportedMs: 12, primaryPoolDirectMs: 30).effectiveLatencyMs(usingFallback: false) == 12)
        #expect(PoolLatencyMeasurement(primaryPoolDirectMs: 30).effectiveLatencyMs(usingFallback: true) == 30)
        #expect(PoolLatencyMeasurement(primaryPoolDirectMs: 30, fallbackPoolDirectMs: 50).effectiveLatencyMs(usingFallback: true) == 50)
        #expect(PoolLatencyMeasurement().effectiveLatencyMs(usingFallback: false) == nil)
    }

    @Test(arguments: [
        (nil, LatencyQuality.unavailable), (0.0, .unavailable), (20.0, .excellent),
        (45.0, .good), (99.9, .good), (150.0, .fair), (250.0, .poor),
    ] as [(Double?, LatencyQuality)])
    func latencyQuality(ms: Double?, expected: LatencyQuality) {
        #expect(LatencyQuality.evaluate(ms) == expected)
    }

    @Test func connectionState() {
        #expect(MinerConnectionState.online.isOnline)
        #expect(!MinerConnectionState.checking.isOnline)
        #expect(!MinerConnectionState.offline(reason: "x").isOnline)
    }
}
