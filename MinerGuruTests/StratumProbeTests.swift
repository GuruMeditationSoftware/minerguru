import Foundation
import Testing
@testable import MinerGuru

@Suite("Stratum probe")
struct StratumProbeTests {
    private static let genesis = "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"
    private static let genesisScript = "76a91462e907b15cbf27d5425399ebf6f0fb50ebb88f1888ac"

    // MARK: - Addresses

    @Test(arguments: [
        genesis,
        "bitcoincash:qp3wjpa3tjlj042z2wv7hahsldgwhwy0rq9sywjpyy",
        "qp3wjpa3tjlj042z2wv7hahsldgwhwy0rq9sywjpyy",
        "ecash:qp3wjpa3tjlj042z2wv7hahsldgwhwy0rquas9fmzn",
        "solo:\(genesis)",
    ])
    func sameKeyGivesTheSameScript(address: String) {
        #expect(CoinAddress.scriptPubKey(for: address).map(Self.hex) == Self.genesisScript)
    }

    @Test(arguments: [
        ("bc1q28kkr5hk4gnqe3evma6runjrd2pvqyp8fpwfzu", MinedCoin.btc),
        ("bc1p5d7rjq7g6rdk2yhzks9smlaqtedr4dekq08ge8ztwac72sfr9rusxg3297", .btc),
        ("3LyFQTKbPwXtgrsGpMbbEECY7ViBeFbonU", .btc),
        ("DRNiw2k4iFuHGS2fF1wMahounXo6H9iGbh", .dgb),
        ("dgb1qdxxrkdx4m9r7hlqa6smwzwawfen56nndrnze36", .dgb),
        ("bitcoincash:qp3wjpa3tjlj042z2wv7hahsldgwhwy0rq9sywjpyy", .bch),
        ("ecash:qp3wjpa3tjlj042z2wv7hahsldgwhwy0rquas9fmzn", .xec),
    ])
    func addressesSurviveTheRoundTrip(address: String, coin: MinedCoin) throws {
        let script = try #require(CoinAddress.scriptPubKey(for: address))
        #expect(CoinAddress.address(for: script, coin: coin) == address)
    }

    @Test(arguments: ["myaccount", "bc1q28kkr5hk4gnqe3evma6runjrd2pvqyp8fpwfzv", "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNb", ""])
    func accountNamesAndTyposAreNoAddress(value: String) {
        #expect(CoinAddress.scriptPubKey(for: value) == nil)
    }

    // MARK: - Recorded pools

    @Test(arguments: StratumCapture.all)
    func probeReadsTheRecordedTemplate(capture: StratumCapture) throws {
        var session = StratumProbeSession(user: capture.user, userAgent: "test")
        var event: StratumProbeSession.Event?
        for line in try capture.lines() where event == nil {
            event = session.receive(line)
        }

        guard capture.authorized else {
            #expect(event == .failed(.rejected("Invalid address")))
            return
        }
        guard case .job(let job) = event else {
            Issue.record("no job: \(String(describing: event))")
            return
        }
        #expect(job.merkleBranchCount == capture.merkleBranches)

        let coinbase = try #require(job.coinbase)
        #expect(coinbase.height == capture.height)
        #expect(Double(coinbase.totalSats) == capture.totalSats)
        let expected = capture.outputs ?? []
        #expect(coinbase.outputs.map { Double($0.valueSats) } == expected.map { $0.value ?? 0 })
        #expect(coinbase.outputs.map { Self.hex($0.script) } == expected.map { $0.scriptPubKey ?? "" })

        // The recording printed every address in Bitcoin notation; BCH and eCash use CashAddr here.
        let coin = MinedCoin(rawValue: capture.coin) ?? .unknown
        if [.btc, .dgb, .bsv].contains(coin) {
            for (output, reference) in zip(coinbase.outputs, expected) where reference.address != nil {
                #expect(CoinAddress.address(for: output.script, coin: coin) == reference.address)
            }
        }

        let block = try #require(BlockTemplateSummary(job: job, coin: coin, stratumUser: capture.user))
        let paysUs = expected.contains(where: \.paysTestAddress)
        #expect(block.payoutState == (paysUs ? .verified : .notFound))
        #expect(((block.userSats ?? 0) > 0) == paysUs)
        #expect(block.outputs.count + block.othersCount == expected.count)
    }

    @Test func sharedCoinbaseListsTheLargestAndSumsTheRest() throws {
        let ocean = try #require(StratumCapture.all.first { $0.file == "ocean-btc.jsonl" })
        let block = try #require(Self.block(from: ocean))
        let payers = block.outputs.filter { !$0.isDataOutput }
        #expect(payers.count == BlockTemplateSummary.maxListedRecipients)
        #expect(block.othersCount > 0)
        let listed = block.outputs.reduce(0) { $0 + $1.valueSats }
        #expect(listed + block.othersValueSats == block.totalSats)
    }

    @Test func nerdminersWorksWithoutExtranonce() throws {
        let capture = try #require(StratumCapture.all.first { $0.file == "nerdminers-btc.jsonl" })
        let block = try #require(Self.block(from: capture))
        #expect(block.payoutState == .verified)
        #expect(block.poolTag?.contains("nerdminers") == true)
        #expect(block.transactionRange == 2049...4096)
    }

    /// The branch count comes from the pool; 63 or 65 branches used to crash the shift into a range.
    @Test(arguments: [63, 64, 65, 1000])
    func oversizedMerkleBranchesDoNotCrash(branches: Int) throws {
        let capture = try #require(StratumCapture.all.first { $0.file == "nerdminers-btc.jsonl" })
        var job = try #require(Self.job(from: capture))
        job.merkleBranchCount = branches
        let block = try #require(BlockTemplateSummary(job: job, coin: .btc, stratumUser: capture.user))
        #expect(block.transactionRange == (1 << 29) + 1...(1 << 30))
    }

    @Test func witnessCommitmentReadsLikeTheFirmwareReportsIt() throws {
        let capture = try #require(StratumCapture.all.first { $0.file == "ckpool-eu-btc.jsonl" })
        let block = try #require(Self.block(from: capture))
        #expect(block.outputs.contains { $0.isWitnessCommitment })
        #expect(block.outputs.first?.address == Self.genesis)
    }

    @Test func accountUserIsNotChecked() throws {
        let capture = try #require(StratumCapture.all.first { $0.file == "kryptex-bsv.jsonl" })
        let job = try #require(Self.job(from: capture))
        let block = try #require(BlockTemplateSummary(job: job, coin: .bsv, stratumUser: "myaccount.worker1"))
        #expect(block.payoutState == .notApplicable)
    }

    // MARK: - Session

    @Test func jobBeforeAuthorizeResultCounts() {
        var session = StratumProbeSession(user: "\(Self.genesis).minerguru", userAgent: "test")
        #expect(session.openingLines.count == 2)
        #expect(session.openingLines[1].contains("mining.authorize"))
        #expect(session.receive(#"{"id":1,"result":[[["mining.notify","ab"]],"f000000f",8],"error":null}"#) == nil)
        let event = session.receive(#"{"id":null,"method":"mining.notify","params":["1","00","01","02",[],"20000000","1703a30c","6900f0a0",true]}"#)
        guard case .job(let job) = event else {
            Issue.record("expected a job")
            return
        }
        #expect(job.extranonce1 == "f000000f")
        #expect(job.extranonce2Size == 8)
    }

    @Test func probeNeverSubmits() {
        let session = StratumProbeSession(user: "x", userAgent: "test")
        #expect(!session.openingLines.contains { $0.contains("mining.submit") })
    }

    // MARK: - Live

    /// Real connection, run by hand: `MINERGURU_LIVE_PROBE=1 swift test --filter liveProbe`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MINERGURU_LIVE_PROBE"] != nil), arguments: [
        ("eusolo.ckpool.org", 3333),
        ("public-pool.io", 21496),
    ])
    func liveProbe(host: String, port: Int) async throws {
        let job = try await StratumProbe.fetchJob(host: host, port: port, tls: false, user: "\(Self.genesis).minerguru")
        let block = try #require(BlockTemplateSummary(job: job, coin: .btc, stratumUser: "\(Self.genesis).bitaxe"))
        print("live \(host): height \(block.height), tag \(block.poolTag ?? "-"), state \(block.payoutState)")
        #expect(block.height > 900_000)
        #expect(block.payoutState == .verified)
    }

    // MARK: - Helpers

    private static func job(from capture: StratumCapture) -> StratumJob? {
        var session = StratumProbeSession(user: capture.user, userAgent: "test")
        for line in (try? capture.lines()) ?? [] {
            if case .job(let job) = session.receive(line) { return job }
        }
        return nil
    }

    private static func block(from capture: StratumCapture) -> BlockTemplateSummary? {
        job(from: capture).flatMap {
            BlockTemplateSummary(job: $0, coin: MinedCoin(rawValue: capture.coin) ?? .unknown, stratumUser: capture.user)
        }
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
