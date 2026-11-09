import Foundation
import Testing

/// One recorded pool endpoint from `MockMiners/stratum-captures/expected.json`.
struct StratumCapture: CustomTestStringConvertible, Sendable, Decodable {
    struct Output: Sendable, Decodable {
        let type: String?
        let value: Double?
        let address: String?
        let scriptPubKey: String?
        let paysTestAddress: Bool
    }

    let file: String
    let coin: String
    let user: String
    let authorized: Bool
    let totalSats: Double?
    let merkleBranches: Int?
    let extranonce1: String?
    let extranonce2Size: Int?
    /// Nerdminers sends no extranonce; the gap length follows from the scriptSig.
    let extranonceGapBytes: Int?
    let height: Int?
    let outputs: [Output]?

    /// Coinbase as the miner builds it, with an all-zero extranonce2.
    func coinbaseHex(coinb1: String, coinb2: String) -> String {
        if let extranonceGapBytes {
            return coinb1 + String(repeating: "00", count: extranonceGapBytes) + coinb2
        }
        return coinb1 + (extranonce1 ?? "") + String(repeating: "00", count: extranonce2Size ?? 0) + coinb2
    }

    var testDescription: String { file }

    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("MockMiners/stratum-captures")

    static let all: [StratumCapture] = {
        let url = directory.appendingPathComponent("expected.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([StratumCapture].self, from: data)) ?? []
    }()

    /// Every line the pool sent, in order.
    func lines() throws -> [String] {
        try String(contentsOf: Self.directory.appendingPathComponent(file), encoding: .utf8)
            .split(separator: "\n").map(String.init)
    }

    /// Params of the first `mining.notify` the pool sent.
    func firstNotify() throws -> [Any]? {
        let text = try String(contentsOf: Self.directory.appendingPathComponent(file), encoding: .utf8)
        for line in text.split(separator: "\n") {
            guard let message = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  message["method"] as? String == "mining.notify" else { continue }
            return message["params"] as? [Any]
        }
        return nil
    }
}

/// Guards the recorded pool replies that the Stratum probe (MG-04) will be tested against.
@Suite("Stratum captures")
struct StratumCaptureTests {
    @Test func everyRecordedEndpointIsListed() {
        #expect(StratumCapture.all.count == 17)
    }

    @Test(arguments: StratumCapture.all)
    func notifyMatchesTheRecordedTemplate(capture: StratumCapture) throws {
        let notify = try capture.firstNotify()
        guard capture.authorized else {
            #expect(notify == nil)
            return
        }
        let params = try #require(notify)
        #expect(params.count == 9)
        let coinb1Hex = try #require(params[2] as? String)
        let coinb1 = try #require(Self.bytes(coinb1Hex))
        let coinb2 = try #require(params[3] as? String)

        // version (4) + input count (1) + prevout (36) + scriptSig length (1), then the BIP34 height push
        let pushLength = Int(coinb1[42])
        let heightBytes = coinb1[43..<(43 + pushLength)]
        let height = heightBytes.reversed().reduce(0) { $0 << 8 | Int($1) }
        #expect(height == capture.height)

        // Outputs are not always in coinb2: Ocean and solopool.eu BCH put the extranonce into an
        // OP_RETURN output, so earlier outputs sit in coinb1. Search the assembled coinbase.
        let coinbase = capture.coinbaseHex(coinb1: coinb1Hex, coinb2: coinb2)
        for output in capture.outputs ?? [] {
            let script = try #require(output.scriptPubKey)
            #expect(coinbase.contains(script))
        }
    }

    @Test func soloPoolsPayTheTestAddressAndSharedOnesDoNot() {
        let paid = Dictionary(uniqueKeysWithValues: StratumCapture.all.map { capture in
            (capture.file, capture.outputs?.contains(where: \.paysTestAddress) ?? false)
        })
        #expect(paid["ckpool-us-btc.jsonl"] == true)
        #expect(paid["publicpool-btc.jsonl"] == true)
        #expect(paid["ocean-btc.jsonl"] == false)
        #expect(paid["kryptex-bsv.jsonl"] == false)
    }

    private static func bytes(_ hex: String?) -> [UInt8]? {
        guard let hex, hex.count.isMultiple(of: 2) else { return nil }
        var result: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            result.append(byte)
            index = next
        }
        return result
    }
}
