import Foundation
import Testing
@testable import MinerGuru

@Suite("Miner settings form")
struct MinerSettingsFormTests {
    @Test func loadsValuesFromTelemetry() throws {
        let info = try Fixtures.bitaxeInfo(overrides: [
            "frequency": 575, "coreVoltage": 1200, "autofanspeed": 0, "fanspeed": 65,
            "stratumURL": "stratum+tcp://eusolo.ckpool.org:3333", "hostname": "bitaxe-keller",
        ])
        let form = MinerSettingsForm(miner: Fixtures.device(name: "Keller", info: info))
        #expect(form.frequencyMHz == 575)
        #expect(form.coreVoltageMV == 1200)
        #expect(!form.autoFanSpeed)
        #expect(form.manualFanPercent == 65)
        #expect(form.customAlias == "Keller")
        #expect(form.deviceHostname == "bitaxe-keller")
        #expect(form.poolMode == .failover)
        #expect(form.primary.host == "eusolo.ckpool.org") // scheme and port stripped
        #expect(form.primary.port == 3333)
        #expect(form.fallback.host == "public-pool.io")
    }

    @Test func loadsDualPoolSplit() throws {
        let form = MinerSettingsForm(miner: Fixtures.device(info: try Fixtures.dualPoolInfo()))
        #expect(form.poolMode == .dual)
        #expect(form.primaryPercent == 1)
        #expect(form.secondaryPercent == 99)
    }

    @Test func manualFanIsClampedAndDefaultsWhenUnknown() throws {
        let slow = MinerSettingsForm(miner: Fixtures.device(info: try Fixtures.bitaxeInfo(overrides: ["fanspeed": 5])))
        #expect(slow.manualFanPercent == 20)
        let unknown = MinerSettingsForm(miner: Fixtures.device(info: try Fixtures.bitaxeInfo(overrides: ["fanspeed": 0])))
        #expect(unknown.manualFanPercent == 75)
    }

    @Test func withoutTelemetryOnlyTheAliasIsSet() {
        let form = MinerSettingsForm(miner: Fixtures.device(name: "Neu", info: nil))
        var expected = MinerSettingsForm()
        expected.customAlias = "Neu"
        #expect(form == expected)
    }

    @Test func presets() {
        var form = MinerSettingsForm()
        let preset = MinerClockPreset(name: "Eco", subtitle: "", frequencyMHz: 490, coreVoltageMV: 1130)
        #expect(!form.isCurrent(preset))
        form.apply(preset)
        #expect(form.isCurrent(preset))
        #expect(form.frequencyMHz == 490 && form.coreVoltageMV == 1130)
    }

    @Test func performancePayloadKeepsAutoFanMode() {
        var form = MinerSettingsForm()
        form.frequencyMHz = 600
        form.coreVoltageMV = 1250

        let pid = form.performancePayload(existingAutoFanMode: 2)
        #expect(pid.frequency == 600)
        #expect(pid.coreVoltage == 1250)
        #expect(pid.overclockEnabled == 1)
        #expect(pid.autofanspeed == 2) // NerdQAxe PID mode survives
        #expect(pid.fanspeed == nil)

        #expect(form.performancePayload(existingAutoFanMode: 0).autofanspeed == 1)
        #expect(form.performancePayload(existingAutoFanMode: nil).autofanspeed == 1)

        form.autoFanSpeed = false
        form.manualFanPercent = 80
        let manual = form.performancePayload(existingAutoFanMode: 2)
        #expect(manual.autofanspeed == 0)
        #expect(manual.fanspeed == 80)
    }

    @Test func poolPayloadCleansInputAndSkipsEmptyFallback() {
        var form = MinerSettingsForm()
        form.primary = .init(host: " stratum+tcp://solo.ckpool.org:3333 ", port: 3333, user: " bc1qwallet.rig ", password: "")
        form.fallback = .init(host: "", port: 4444, user: "   ", password: "x")

        let payload = form.poolPayload(supportsDualPool: false)
        #expect(payload.stratumURL == "solo.ckpool.org")
        #expect(payload.stratumUser == "bc1qwallet.rig")
        #expect(payload.stratumPassword == nil)
        #expect(payload.fallbackStratumURL == nil)
        #expect(payload.fallbackStratumPort == nil)
        #expect(payload.fallbackStratumUser == nil)
        #expect(payload.poolMode == nil) // firmware without dual-pool support
        #expect(payload.poolBalance == nil)
    }

    @Test func poolPayloadForDualPoolFirmware() {
        var form = MinerSettingsForm()
        form.primary.host = "eusolo.ckpool.org"
        form.fallback = .init(host: "bch.solopool.eu", port: 3333, user: "qq.rig", password: "x")

        #expect(form.poolPayload(supportsDualPool: true).poolMode == 0)
        #expect(form.poolPayload(supportsDualPool: true).poolBalance == nil)

        form.poolMode = .dual
        form.poolBalance = 25
        let dual = form.poolPayload(supportsDualPool: true)
        #expect(dual.poolMode == 1)
        #expect(dual.poolBalance == 25)
        #expect(dual.fallbackStratumURL == "bch.solopool.eu")
        #expect(dual.fallbackStratumPort == 3333)
    }

    @Test func hostnamePayloadIsTrimmed() {
        var form = MinerSettingsForm()
        form.deviceHostname = "  bitaxe-2 \n"
        #expect(form.trimmedHostname == "bitaxe-2")
        #expect(form.hostnamePayload.hostname == "bitaxe-2")
    }

    @Test func dualPoolSupport() throws {
        #expect(Fixtures.device(info: try Fixtures.dualPoolInfo()).supportsDualPool)
        #expect(!Fixtures.device(info: try Fixtures.bitaxeInfo()).supportsDualPool)
    }

    @Test func payloadEncodesOnlySetFields() throws {
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(MinerSystemUpdatePayload(hostname: "x"))) as? [String: Any]
        #expect(json?.keys.sorted() == ["hostname"])
    }
}

@Suite("Miner detail texts")
struct MinerDisplayTextTests {
    @Test func hashrateAverages() throws {
        #expect(try Fixtures.bitaxeInfo(overrides: ["hashRate_1m": 1070, "hashRate_1h": 1065]).hashrateAveragesText
                == "1m: 1.07 TH/s • 1h: 1.06 TH/s")
        #expect(try Fixtures.bitaxeInfo(overrides: ["hashRate_1m": 980]).hashrateAveragesText == "1m Ø: 980 GH/s")
        #expect(try Fixtures.bitaxeInfo(hashRate: 1215.8).hashrateAveragesText == "1216 GH/s Live")
    }

    @Test func fanTexts() throws {
        let single = try Fixtures.bitaxeInfo(overrides: ["fanspeed": 70, "fanrpm": 5299, "autofanspeed": 0])
        #expect(single.fanPercentText == "70")
        #expect(single.fanRPMText == "5299 RPM • Manuell")

        let dual = try Fixtures.bitaxeInfo(overrides: ["fanspeed": 40, "fanrpm": 1248, "fanspeed2": 19, "fanrpm2": 2592, "autofanspeed": 2])
        #expect(dual.fanPercentText == "40 / 19")
        #expect(dual.fanRPMText == "1248 & 2592 RPM • PID Auto")

        #expect(try Fixtures.bitaxeInfo(overrides: ["autofanspeed": 1]).fanModeLabel == "Auto-Modus")
    }

    @Test func coolingText() throws {
        #expect(try Fixtures.bitaxeInfo(overrides: ["vrTemp": 62.0]).coolingText(warningThresholdC: 68) == "Spannungsregler (VR): 62.0 °C")
        #expect(try Fixtures.bitaxeInfo(overrides: ["temp": 55]).coolingText(warningThresholdC: 68) == "Kühlstatus: Optimal")
        #expect(try Fixtures.bitaxeInfo(overrides: ["temp": 70]).coolingText(warningThresholdC: 68) == "Kühlstatus: Erhöht")
    }

    @Test func powerAndShares() throws {
        let info = try Fixtures.bitaxeInfo(power: 18.2, overrides: [
            "voltage": 5160, "current": 11550, "coreVoltage": 1150, "coreVoltageActual": 1144,
            "sharesAccepted": 99, "sharesRejected": 1,
        ])
        #expect(info.powerDetailText == "5.16 V • 11.55 A")
        #expect(info.dailyEnergyText == "~0.44 kWh / 24h")
        #expect(info.coreVoltageText == "Ziel: 1150 mV • Ist: 1144 mV")
        #expect(info.sharesText == "Shares: 99 ok / 1 rej (1.00%)")
    }

    @Test func poolLatencyText() throws {
        let single = Fixtures.device(info: try Fixtures.bitaxeInfo())
        #expect(single.poolLatencyDetailText == "Exzellent • eusolo.ckpool.org")

        let dual = Fixtures.device(info: try Fixtures.dualPoolInfo())
        #expect(dual.poolLatencyDetailText == "Dual (1%/99%) • P1: 20 ms / P2: 30 ms")

        #expect(Fixtures.device(info: nil).poolLatencyDetailText == "—")
        #expect(Fixtures.device(ip: "10.0.0.5").webInterfaceURL?.absoluteString == "http://10.0.0.5")
    }

    @Test func logExportFileName() {
        let name = MinerLogStreamController.exportFileName(
            minerName: "Wohnzimmer / Bitaxe",
            ipAddress: "192.168.1.28",
            date: Date(timeIntervalSince1970: 0),
            timeZone: TimeZone(identifier: "UTC")!
        )
        #expect(name == "MinerGuru-Wohnzimmer-Bitaxe-192.168.1.28-1970-01-01_00-00-00.log")
    }
}

@Suite("Pool per Zeitplan umstellen")
struct SwitchPrimaryTests {
    @Test func keepsAMinerThatAlreadyMinesThere() throws {
        var form = MinerSettingsForm(miner: Fixtures.device(info: try Fixtures.bitaxeInfo()))
        let config = PoolConfig(name: "x", endpoint: form.primary)
        let changed = form.switchPrimary(to: config)
        #expect(!changed)
    }

    @Test func assignsAPoolToThePrimarySlot() throws {
        var form = MinerSettingsForm(miner: Fixtures.device(info: try Fixtures.bitaxeInfo()))
        let config = PoolConfig(name: "lotto", host: "lotto.example.com", user: "bc1qtest")
        let changed = form.switchPrimary(to: config)
        #expect(changed)
        #expect(form.primary.host == "lotto.example.com")
    }
}
