import Foundation
import Testing
@testable import MinerGuru

@Suite("Current block template")
struct BlockTemplateTests {
    /// ckpool-style template: 98 % to the miner, 2 % pool fee, witness commitment.
    private static var decodedFields: [String: Any] { [
        "blockHeight": 974_212,
        "scriptsig": "/solo.ckpool.org/",
        "blockSignals": ["BIP-54"],
        "stratumDecodeCoinbase": true,
        "coinbaseValueTotalSatoshis": 314_000_000,
        "coinbaseValueUserSatoshis": 307_720_000,
        "coinbaseOutputs": [
            ["value": 307_720_000, "address": "bc1qexamplewallet", "isUserOutput": 1],
            ["value": 6_280_000, "address": "bc1qpoolfeeexample", "isUserOutput": 0],
            ["value": 0, "address": "OP_RETURN: .!..a.Xb..9.f..Z.", "isUserOutput": 0],
        ],
        "coinbaseOthersCount": 0,
        "coinbaseOthersValueSatoshis": 0,
    ] }

    @Test func decodesTheAxeOSBlockFields() throws {
        let info = try Fixtures.bitaxeInfo(overrides: Self.decodedFields)
        let block = try #require(BlockTemplateSummary(info: info))

        #expect(block.height == 974_212)
        #expect(block.poolTag == "/solo.ckpool.org/")
        #expect(block.signals == ["BIP-54"])
        #expect(block.coin == .btc)
        #expect(block.outputs.count == 3)
        #expect(block.outputs[0].isUserOutput)
        #expect(block.payoutState == .verified)
        #expect(block.feesSats == 1_500_000)
        #expect(block.userShare == 0.98)
    }

    @Test func witnessCommitmentIsDataNotPayout() {
        let commitment = CoinbaseOutput(valueSats: 0, address: "OP_RETURN: .!..a.Xb..9.f..Z.")
        #expect(commitment.isDataOutput)
        #expect(commitment.isWitnessCommitment)
        #expect(commitment.dataText == nil)

        let tag = CoinbaseOutput(valueSats: 0, address: "OP_RETURN: RSKBLOCK:abc123")
        #expect(!tag.isWitnessCommitment)
        #expect(tag.dataText == "RSKBLOCK:abc123")
    }

    @Test func decodingOffKeepsTheSumButHidesRecipients() throws {
        var fields = Self.decodedFields
        fields["stratumDecodeCoinbase"] = false
        let block = try #require(BlockTemplateSummary(info: try Fixtures.bitaxeInfo(overrides: fields)))

        #expect(block.payoutState == .decodingOff)
        #expect(block.outputs.isEmpty)
        #expect(block.totalSats == 314_000_000)
        #expect(block.userSats == nil)
    }

    @Test func activeSlotDecidesAboutDecoding() throws {
        // AxeOS 2.15: the fallback slot is active and does not decode, the primary does.
        var fields = Self.decodedFields
        fields["isUsingFallbackStratum"] = 1
        fields["primaryPoolIndex"] = 0
        fields["secondaryPoolIndex"] = 1
        fields["pools"] = [
            ["id": 0, "stratumURL": "eusolo.ckpool.org", "stratumUser": "bc1qexamplewallet.bitaxe", "stratumDecodeCoinbase": true],
            ["id": 1, "stratumURL": "public-pool.io", "stratumUser": "bc1qexamplewallet.bitaxe", "stratumDecodeCoinbase": false],
        ]
        let info = try Fixtures.bitaxeInfo(overrides: fields)
        #expect(info.activePoolDecodesCoinbase == false)
        #expect(BlockTemplateSummary(info: info)?.payoutState == .decodingOff)
    }

    @Test func leftoverSumFromAnUndecodedJobIsIgnored() throws {
        var fields = Self.decodedFields
        fields["coinbaseValueTotalSatoshis"] = 3.179677500620704e17
        let block = try #require(BlockTemplateSummary(info: try Fixtures.bitaxeInfo(overrides: fields)))

        #expect(block.totalSats == nil)
        #expect(block.feesSats == nil)
        #expect(block.userShare == nil)
    }

    @Test(arguments: [
        ("verified", BlockTemplateSummary.PayoutState.verified),
        ("not_found", .notFound),
        ("not_applicable", .notApplicable),
    ])
    func firmwareStatusWins(raw: String, expected: BlockTemplateSummary.PayoutState) throws {
        var fields = Self.decodedFields
        fields["coinbasePayoutStatus"] = raw
        let block = try #require(BlockTemplateSummary(info: try Fixtures.bitaxeInfo(overrides: fields)))
        #expect(block.payoutState == expected)
    }

    @Test func missingOwnAddressIsDerivedOnOlderFirmware() throws {
        var fields = Self.decodedFields
        fields["coinbaseValueUserSatoshis"] = 0
        fields["coinbaseOutputs"] = [["value": 314_000_000, "address": "bc1qsomeoneelse", "isUserOutput": 0]]
        fields["stratumUser"] = "bc1q7n70rumyv6lvu8avpml0c3uggvssfu52egum3q.nerdqaxe"
        #expect(BlockTemplateSummary(info: try Fixtures.bitaxeInfo(overrides: fields))?.payoutState == .notFound)

        fields["stratumUser"] = "myaccount.worker1"
        #expect(BlockTemplateSummary(info: try Fixtures.bitaxeInfo(overrides: fields))?.payoutState == .notApplicable)
    }

    @Test func noBlockDataWithoutHeight() throws {
        #expect(BlockTemplateSummary(info: try Fixtures.bitaxeInfo()) == nil)
        #expect(BlockTemplateSummary(info: try Fixtures.bitaxeInfo(overrides: ["blockHeight": 0])) == nil)
        #expect(BlockTemplateSummary(info: try Fixtures.dualPoolInfo()) == nil)
    }

    @Test(arguments: [
        (840_000, MinedCoin.btc, 312_500_000.0 as Double?),
        (1_049_999, .btc, 312_500_000),
        (1_050_000, .btc, 156_250_000),
        (900_000, .bch, 312_500_000),
        (20_000_000, .dgb, nil),
    ])
    func subsidyFollowsTheHalvings(height: Int, coin: MinedCoin, expected: Double?) {
        #expect(BlockTemplateSummary.subsidySats(height: height, coin: coin) == expected)
    }

    @Test func blockFieldsSurviveEncoding() throws {
        let info = try Fixtures.bitaxeInfo(overrides: Self.decodedFields)
        let roundTrip = try JSONDecoder().decode(MinerSystemInfo.self, from: JSONEncoder().encode(info))
        #expect(roundTrip == info)
    }

    @Test(arguments: MinerVariant.all)
    func variantsReportBlockDataFromAxeOS213(variant: MinerVariant) throws {
        let info = try variant.load()
        let version = info.firmwareVersion.dropFirst().split(separator: ".").compactMap { Int($0) }
        let hasBlockData = variant.firmware == .axeOS && version.lexicographicallyPrecedes([2, 13]) == false
        #expect((BlockTemplateSummary(info: info) != nil) == hasBlockData)
    }
}
