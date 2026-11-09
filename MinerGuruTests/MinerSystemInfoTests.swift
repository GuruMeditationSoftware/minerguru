import XCTest
@testable import MinerGuru

final class MinerSystemInfoTests: XCTestCase {
    func testDecodeBitaxeGamma601Payload() throws {
        let json = """
        {
          "power": 18.2,
          "voltage": 5060,
          "current": 3590,
          "temp": 56.4,
          "vrTemp": 49.0,
          "hashRate": 1215.8,
          "hashRate_1m": 1205.0,
          "hashRate_1h": 1198.4,
          "bestDiff": 452000000,
          "bestSessionDiff": 12800000,
          "stratumURL": "public-pool.io",
          "stratumPort": 21496,
          "stratumUser": "bc1qexamplewallet.gamma601",
          "fallbackStratumURL": "eusolo.ckpool.org",
          "fallbackStratumPort": 3333,
          "fallbackStratumUser": "bc1qexamplewallet.gamma601",
          "isUsingFallbackStratum": 0,
          "responseTime": 21.6,
          "sharesAccepted": 842,
          "sharesRejected": 1,
          "uptimeSeconds": 172800,
          "asicCount": 1,
          "smallCoreCount": 2040,
          "ASICModel": "BM1370",
          "boardVersion": "601",
          "hostname": "bitaxe-gamma",
          "version": "v2.5.1",
          "fanspeed": 65,
          "fanrpm": 4350,
          "autofanspeed": 1,
          "coreVoltage": 1150,
          "coreVoltageActual": 1146,
          "frequency": 525
        }
        """

        let info = try JSONDecoder().decode(MinerSystemInfo.self, from: Data(json.utf8))
        XCTAssertEqual(info.detectedHardwareTitle, "Bitaxe Gamma 601")
        XCTAssertEqual(info.hashRate, 1215.8, accuracy: 0.01)
        XCTAssertEqual(info.voltageVolts, 5.06, accuracy: 0.01)
        XCTAssertEqual(info.currentAmps, 3.59, accuracy: 0.01)
        XCTAssertEqual(info.minerReportedPoolLatencyMs ?? 0, 21.6, accuracy: 0.01)
        XCTAssertEqual(info.bestDiffFormatted, "452M")
        XCTAssertEqual(info.activeWorkerName, "gamma601")
        XCTAssertFalse(info.isUsingFallbackStratum)
        XCTAssertEqual(info.efficiencyJPerTH, 18.2 / 1.2158, accuracy: 0.05)
    }

    func testDecodeNerdQAxePlusPlusPayload() throws {
        let json = """
        {
          "hashRate": 4820.5,
          "hashRate_1m": 4795.2,
          "hashRate_1h": 4780.0,
          "temp": 54.2,
          "vrTemp": 46.5,
          "power": 72.4,
          "voltage": 12.08,
          "current": 5.99,
          "fanspeed": 80,
          "fanrpm": 5200,
          "autofanspeed": 1,
          "sharesAccepted": 1420,
          "sharesRejected": 2,
          "bestDiff": "1.25G",
          "bestSessionDiff": "340M",
          "coreVoltage": 1150,
          "coreVoltageActual": 1145,
          "frequency": 525,
          "stratum": {
            "poolMode": 0,
            "activePoolMode": 0,
            "usingFallback": false,
            "pools": [
              {
                "active": true,
                "connected": true,
                "poolDifficulty": 10000,
                "responseTime": 17.8
              }
            ]
          },
          "stratumURL": "public-pool.io",
          "stratumPort": 21496,
          "stratumUser": "bc1qexamplewallet.nerdqaxe",
          "fallbackStratumURL": "solo.ckpool.org",
          "fallbackStratumPort": 3333,
          "fallbackStratumUser": "bc1qexamplewallet.nerdqaxe",
          "deviceModel": "NerdQAxePlusPlus",
          "ASICModel": "BM1370",
          "hostname": "nerdqaxe-pp",
          "version": "1.1.0",
          "uptime": 345600
        }
        """

        let info = try JSONDecoder().decode(MinerSystemInfo.self, from: Data(json.utf8))
        XCTAssertEqual(info.detectedHardwareTitle, "NerdQAxe++")
        XCTAssertEqual(info.asicCount, 4)
        XCTAssertEqual(info.minerReportedPoolLatencyMs ?? 0, 17.8, accuracy: 0.01)
        XCTAssertEqual(info.activePoolDifficulty ?? 0, 10000, accuracy: 0.1)
        XCTAssertEqual(info.bestDiffFormatted, "1.25G")
        XCTAssertEqual(info.bestDiffNumeric, 1_250_000_000, accuracy: 1)
        XCTAssertEqual(info.uptimeSeconds, 345600)
        XCTAssertFalse(info.isDualPoolMining)
    }

    func testDecodeNerdQAxePlusPlusDualPoolPayload() throws {
        let json = """
        {
          "deviceModel": "NerdQAxe++",
          "hostip": "192.168.1.33",
          "power": 100.125,
          "voltage": 12218.75,
          "current": 7843.75,
          "temp": 60,
          "vrTemp": 57,
          "hashRate": 6213.437,
          "bestDiff": 20494162828,
          "bestSessionDiff": 790846423,
          "isUsingFallbackStratum": 0,
          "stratum": {
            "poolMode": 1,
            "activePoolMode": 1,
            "poolBalance": 1,
            "usingFallback": false,
            "totalBestDiff": 20494162828,
            "pools": [
              {
                "connected": true,
                "poolDifficulty": 1000,
                "accepted": 2911,
                "rejected": 1,
                "pingRtt": 22,
                "pingLoss": 0,
                "bestDiff": 1030328
              },
              {
                "connected": true,
                "poolDifficulty": 3075,
                "accepted": 98920,
                "rejected": 24,
                "pingRtt": 26.71,
                "pingLoss": 0,
                "bestDiff": 790846423
              }
            ]
          },
          "stratumURL": "eusolo.ckpool.org",
          "stratumPort": 3333,
          "stratumUser": "bc1qexample.NerdQaxe",
          "fallbackStratumURL": "bch.solopool.eu",
          "fallbackStratumPort": 3333,
          "fallbackStratumUser": "qqexample.NerdQaxe",
          "sharesAccepted": 101831,
          "sharesRejected": 25,
          "uptimeSeconds": 117987,
          "asicCount": 4,
          "smallCoreCount": 2040,
          "ASICModel": "BM1370",
          "hostname": "nerdqaxe",
          "version": "v1.1.0",
          "fanspeed": 40,
          "fanrpm": 1284,
          "fanspeed2": 19,
          "fanrpm2": 2702,
          "autofanspeed": 2,
          "coreVoltage": 1200,
          "coreVoltageActual": 1201,
          "frequency": 650
        }
        """

        let info = try JSONDecoder().decode(MinerSystemInfo.self, from: Data(json.utf8))
        XCTAssertTrue(info.isDualPoolMining)
        XCTAssertEqual(info.dualPoolPrimaryPercent, 1)
        XCTAssertEqual(info.dualPoolSecondaryPercent, 99)
        XCTAssertEqual(info.primaryPoolMinerLatencyMs ?? 0, 22.0, accuracy: 0.01)
        XCTAssertEqual(info.secondaryPoolMinerLatencyMs ?? 0, 26.71, accuracy: 0.01)
        XCTAssertEqual(info.fan2RPM, 2702)
        XCTAssertEqual(info.fan2SpeedPercent ?? 0, 19.0, accuracy: 0.01)
        XCTAssertTrue(info.autoFanSpeed)
        XCTAssertEqual(info.autoFanModeRaw, 2)
        XCTAssertEqual(info.primaryPoolCoin, .btc)
        XCTAssertEqual(info.secondaryPoolCoin, .bch)
        XCTAssertEqual(info.activeCoinsSummary, "BTC (1%) + BCH (99%)")
    }

    func testFormatDifficultyNumberUsesThreeSignificantDigits() {
        XCTAssertEqual(MinerSystemInfo.formatDifficultyNumber(0), "0")
        XCTAssertEqual(MinerSystemInfo.formatDifficultyNumber(950), "950")
        XCTAssertEqual(MinerSystemInfo.formatDifficultyNumber(4_400_000_000), "4.40G")
        XCTAssertEqual(MinerSystemInfo.formatDifficultyNumber(20_490_000_000), "20.49G")
        XCTAssertEqual(MinerSystemInfo.formatDifficultyNumber(452_000_000), "452M")
        XCTAssertEqual(MinerSystemInfo.formatDifficultyNumber(141_000_000_000_000), "141T")
    }
}
