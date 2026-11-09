import Testing
@testable import MinerGuru

@Suite("Coin detection per pool")
struct CoinDetectionTests {
    @Test(arguments: [
        ("bch.solopool.eu", "", MinedCoin.bch),
        ("pool.bitcoincash.example", "", .bch),
        ("dgb.pool.example", "", .dgb),
        ("digibyte-pool.example", "", .dgb),
        ("xec.pool.example", "", .xec),
        ("fractal.pool.example", "", .fb),
        ("bsv.pool.example", "", .bsv),
        ("peercoin.pool.example", "", .ppc),
        ("namecoin.pool.example", "", .nmc),
    ])
    func detectsCoinFromPoolHostname(host: String, user: String, expected: MinedCoin) {
        #expect(MinedCoin.detect(poolHost: host, stratumUser: user) == expected)
    }

    @Test(arguments: [
        ("bc1qexamplewallet.worker", MinedCoin.btc),
        ("bc1pexample.worker", .btc),
        ("bitcoincash:qqexample.worker", .bch),
        ("ecash:qqexample.worker", .xec),
        ("dgb1qexample.worker", .dgb),
        ("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa.worker", .btc),
        ("3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy", .btc),
    ])
    func detectsCoinFromWalletAddress(user: String, expected: MinedCoin) {
        #expect(MinedCoin.detect(poolHost: "pool.example", stratumUser: user) == expected)
    }

    @Test func detectsCashAddrWithoutPrefix() {
        let cashAddr = String(repeating: "q", count: 42)
        #expect(MinedCoin.detect(poolHost: "pool.example", stratumUser: "\(cashAddr).worker") == .bch)
    }

    @Test func detectsLegacyDigiByteAddress() {
        let address = "D" + String(repeating: "x", count: 33)
        #expect(MinedCoin.detect(poolHost: "pool.example", stratumUser: address) == .dgb)
    }

    @Test(arguments: [
        (141e12, MinedCoin.btc),
        (462e9, .bch),
        (120e6, .dgb),
        (500.0, .unknown),
    ])
    func fallsBackToNetworkDifficulty(difficulty: Double, expected: MinedCoin) {
        #expect(MinedCoin.detect(poolHost: "pool.example", stratumUser: "worker", networkDifficulty: difficulty) == expected)
    }

    @Test func hostnameWinsOverWallet() {
        // A BCH pool with a BTC-looking worker string is still BCH.
        #expect(MinedCoin.detect(poolHost: "bch.solopool.eu", stratumUser: "bc1qexample.worker") == .bch)
    }

    @Test func knownBitcoinPoolsWithoutWallet() {
        #expect(MinedCoin.detect(poolHost: "eusolo.ckpool.org", stratumUser: "worker") == .btc)
        #expect(MinedCoin.detect(poolHost: "public-pool.io", stratumUser: "") == .btc)
    }

    @Test func unknownWhenNoSignal() {
        #expect(MinedCoin.detect(poolHost: "", stratumUser: "") == .unknown)
        #expect(MinedCoin.detect(poolHost: "some.pool", stratumUser: "worker") == .unknown)
    }
}

@Suite("Address and pool coin")
struct CoinMismatchTests {

    @Test func aBitcoinCashAddressOnABitcoinPoolIsFlagged() {
        let coins = MinedCoin.mismatch(poolHost: "eusolo.ckpool.org", stratumUser: "bitcoincash:qq1234.rig")
        #expect(coins?.pool == .btc)
        #expect(coins?.address == .bch)
    }

    @Test func aBitcoinAddressOnABitcoinCashPoolIsFlagged() {
        #expect(MinedCoin.mismatch(poolHost: "bch.solopool.eu", stratumUser: "bc1qabc.rig")?.address == .btc)
    }

    @Test(arguments: [
        ("eusolo.ckpool.org", "bc1qabc.rig"),           // fits
        ("eusolo.ckpool.org", "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa.rig"), // legacy fits several coins
        ("pool.example", "bitcoincash:qq1234.rig"),     // unknown pool
        ("eusolo.ckpool.org", "account.rig"),           // no address
        ("notckpool.org", "bitcoincash:qq1234.rig"),    // only a name ending alike
    ])
    func noWarning(host: String, user: String) {
        #expect(MinedCoin.mismatch(poolHost: host, stratumUser: user) == nil)
    }
}
