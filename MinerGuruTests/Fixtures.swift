import Foundation
@testable import MinerGuru

/// Builders for test data.
enum Fixtures {
    /// Decodes a `MinerSystemInfo` from a JSON-like dictionary (as returned by `/api/system/info`).
    static func info(_ fields: [String: Any]) throws -> MinerSystemInfo {
        let data = try JSONSerialization.data(withJSONObject: fields)
        return try JSONDecoder().decode(MinerSystemInfo.self, from: data)
    }

    /// Single-pool Bitaxe mining BTC on ckpool.
    static func bitaxeInfo(hashRate: Double = 1000, power: Double = 18, overrides: [String: Any] = [:]) throws -> MinerSystemInfo {
        var fields: [String: Any] = [
            "hashRate": hashRate,
            "power": power,
            "temp": 55.0,
            "sharesAccepted": 900,
            "sharesRejected": 3,
            "bestDiff": 4_400_000_000,
            "stratumURL": "eusolo.ckpool.org",
            "stratumPort": 3333,
            "stratumUser": "bc1qexamplewallet.bitaxe",
            "fallbackStratumURL": "public-pool.io",
            "fallbackStratumPort": 21496,
            "fallbackStratumUser": "bc1qexamplewallet.bitaxe",
            "isUsingFallbackStratum": 0,
            "responseTime": 25.0,
            "ASICModel": "BM1370",
            "boardVersion": "601",
            "hostname": "bitaxe",
            "version": "v2.15.3",
        ]
        fields.merge(overrides) { _, new in new }
        return try info(fields)
    }

    /// NerdQAxe++ in dual-pool mode: 1 % BTC (ckpool) / 99 % BCH (solopool).
    static func dualPoolInfo(hashRate: Double = 6000, btcNetworkDifficulty: Double? = nil) throws -> MinerSystemInfo {
        var pool1: [String: Any] = ["connected": true, "pingRtt": 20.0, "accepted": 10, "rejected": 0]
        if let btcNetworkDifficulty { pool1["networkDifficulty"] = btcNetworkDifficulty }
        return try info([
            "deviceModel": "NerdQAxe++",
            "hashRate": hashRate,
            "power": 77.0,
            "temp": 55.0,
            "stratum": [
                "poolMode": 1,
                "activePoolMode": 1,
                "poolBalance": 1,
                "usingFallback": false,
                "pools": [
                    pool1,
                    ["connected": true, "pingRtt": 30.0, "accepted": 1000, "rejected": 2],
                ],
            ],
            "stratumURL": "eusolo.ckpool.org",
            "stratumPort": 3333,
            "stratumUser": "bc1qexample.nerdqaxe",
            "fallbackStratumURL": "bch.solopool.eu",
            "fallbackStratumPort": 3333,
            "fallbackStratumUser": "qqexample.nerdqaxe",
            "asicCount": 4,
            "ASICModel": "BM1370",
            "hostname": "nerdqaxe",
        ])
    }

    /// Bitaxe on AxeOS 2.15+ with three pool slots (0 primary, 1 fallback, 4 reserve with TLS).
    static func axeSlotsInfo() throws -> MinerSystemInfo {
        try bitaxeInfo(overrides: [
            "primaryPoolIndex": 0,
            "secondaryPoolIndex": 1,
            "pools": [
                ["id": 0, "stratumProtocol": "SV1", "stratumURL": "eusolo.ckpool.org", "stratumPort": 3333,
                 "stratumUser": "bc1qexamplewallet.bitaxe", "stratumPassword": "*****", "stratumTLS": 0,
                 "stratumSuggestedDifficulty": 1000, "stratumDecodeCoinbase": true],
                ["id": 1, "stratumURL": "public-pool.io", "stratumPort": 21496,
                 "stratumUser": "bc1qexamplewallet.bitaxe", "stratumPassword": "*****"],
                ["id": 4, "stratumURL": "mine.ocean.xyz", "stratumPort": 3334, "stratumUser": "bc1qocean.rig",
                 "stratumPassword": "*****", "stratumTLS": 1, "stratumProtocol": "SV2"],
                ["stratumURL": "broken-slot-without-id"],
            ],
        ])
    }

    static func device(
        ip: String = "192.168.1.28",
        name: String? = nil,
        state: MinerConnectionState = .online,
        info: MinerSystemInfo? = nil,
        latency: PoolLatencyMeasurement? = nil
    ) -> MinerDevice {
        MinerDevice(
            config: PersistedMinerConfig(ipAddress: ip, customName: name),
            connectionState: state,
            latestInfo: info,
            poolLatency: latency
        )
    }

    /// Isolated `UserDefaults` so tests never touch the real app settings.
    static func defaults() -> UserDefaults {
        let suite = "MinerGuruTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    static func json(_ string: String) -> Data {
        Data(string.utf8)
    }
}
