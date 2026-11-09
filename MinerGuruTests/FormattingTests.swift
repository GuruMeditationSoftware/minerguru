import Foundation
import Testing
@testable import MinerGuru

@Suite("DisplayFormat (German notation)")
struct DisplayFormatTests {
    @Test func decimalUsesGermanSeparators() {
        #expect(DisplayFormat.decimal(1234.5, fractionDigits: 2) == "1.234,50")
        #expect(DisplayFormat.decimal(3.125, maxFractionDigits: 3) == "3,125")
        #expect(DisplayFormat.decimal(3.0, maxFractionDigits: 3) == "3")
    }

    @Test func percentages() {
        #expect(DisplayFormat.percent(1.234, fractionDigits: 2) == "1,23 %")
    }
}

@Suite("MinerFormatting (AxeOS dot notation)")
struct MinerFormattingTests {
    @Test func hashrate() {
        #expect(MinerFormatting.formatHashrate(0) == "0 GH/s")
        #expect(MinerFormatting.formatHashrate(980.4) == "980 GH/s")
        #expect(MinerFormatting.formatHashrate(1215.8) == "1.22 TH/s")
        #expect(MinerFormatting.splitHashrate(4470) == ("4.47", "TH/s"))
        #expect(MinerFormatting.splitHashrate(0) == ("0", "GH/s"))
    }

    @Test(arguments: [(0, "—"), (59, "1m"), (3_660, "1h 1m"), (90_061, "1d 1h 1m")])
    func uptime(seconds: Int, expected: String) {
        #expect(MinerFormatting.formatUptime(seconds) == expected)
    }

    @Test func latency() {
        #expect(MinerFormatting.formatLatency(nil) == "—")
        #expect(MinerFormatting.formatLatency(0) == "—")
        #expect(MinerFormatting.formatLatency(5.26) == "5.3 ms")
        #expect(MinerFormatting.formatLatency(23.6) == "24 ms")
    }
}

@Suite("Difficulty values")
struct DifficultyTests {
    @Test(arguments: [
        (0.0, "0"), (950.0, "950"), (4_400_000_000.0, "4.40G"),
        (20_490_000_000.0, "20.49G"), (452_000_000.0, "452M"), (141_000_000_000_000.0, "141T"),
    ])
    func formatUsesThreeSignificantDigits(value: Double, expected: String) {
        #expect(MinerSystemInfo.formatDifficultyNumber(value) == expected)
    }

    @Test(arguments: [
        ("1.25G", 1_250_000_000.0), ("340M", 340_000_000.0), ("4.4 k", 4_400.0),
        ("12345", 12_345.0), ("", 0.0), ("abc", 0.0), ("2P", 2e15),
    ])
    func parse(raw: String, expected: Double) {
        #expect(MinerSystemInfo.parseDifficultyString(raw) == expected)
    }

    @Test func formatAndParseRoundTrip() {
        let value = 20_490_000_000.0
        #expect(MinerSystemInfo.parseDifficultyString(MinerSystemInfo.formatDifficultyNumber(value)) == value)
    }
}

@Suite("Host and address normalization")
struct HostNormalizationTests {
    @Test func stratumHostStripsSchemePathAndPort() {
        #expect(StratumHost.clean("stratum+tcp://eusolo.ckpool.org:3333/x") == "eusolo.ckpool.org")
        #expect(StratumHost.clean("stratum+tcp://eusolo.ckpool.org:3333/x", keepPort: true) == "eusolo.ckpool.org:3333")
        #expect(StratumHost.clean("  STRATUM+SSL://Pool.Example  ") == "Pool.Example")
        #expect(StratumHost.clean("public-pool.io") == "public-pool.io")
        #expect(StratumHost.clean("") == "")
    }

    @Test func minerHost() {
        #expect(MinerAPIClient.normalizeHost("  http://192.168.1.28/api/system ") == "192.168.1.28")
        #expect(MinerAPIClient.normalizeHost("HTTPS://bitaxe.local/") == "bitaxe.local")
        #expect(MinerAPIClient.normalizeHost("bitaxe.fritz.box") == "bitaxe.fritz.box")
    }

    @Test func subnetPrefix() {
        #expect(NetworkScanner.normalizePrefix("192.168.1.55") == "192.168.1")
        #expect(NetworkScanner.normalizePrefix(" 10.0.0 ") == "10.0.0")
        #expect(NetworkScanner.normalizePrefix("10.0") == "10.0")
    }

    @Test func ipSortKeyOrdersNumerically() {
        #expect(NetworkScanner.ipSortKey("192.168.1.9") < NetworkScanner.ipSortKey("192.168.1.10"))
        #expect(NetworkScanner.ipSortKey("10.0.0.1") < NetworkScanner.ipSortKey("192.168.0.1"))
        #expect(NetworkScanner.ipSortKey("bitaxe.local") == 0)
    }

    @Test(arguments: [
        ("192.168.1.2", true), ("10.1.2.3", true), ("172.16.0.1", true), ("172.31.255.1", true),
        ("172.32.0.1", false), ("8.8.8.8", false), ("100.64.0.1", false),
    ])
    func privateIPv4(ip: String, expected: Bool) {
        #expect(NetworkScanner.isPrivateIPv4(ip) == expected)
    }
}
