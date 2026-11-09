import Foundation

extension BlockTemplateSummary {
    /// Recipients shown one by one; shared coinbases (Ocean) list the rest as a sum.
    static let maxListedRecipients = 6

    /// Template read by the Stratum probe. `stratumUser` is the miner's own user, so the check
    /// answers whether the pool pays the miner's address, not the probe's worker name.
    init?(job: StratumJob, coin: MinedCoin, stratumUser: String, probedAt: Date = Date()) {
        guard let coinbase = job.coinbase, let height = coinbase.height, height > 0 else { return nil }
        let wallet = stratumUser.split(separator: ".", maxSplits: 1).first.map(String.init) ?? ""
        let userScript = CoinAddress.scriptPubKey(for: wallet)

        let all = coinbase.outputs.map { output in
            CoinbaseOutput(
                valueSats: Double(output.valueSats),
                address: Self.label(for: output.script, coin: coin),
                isUserOutput: userScript != nil && output.script == userScript
            )
        }
        let listedPayers = Set(
            all.indices
                .filter { !all[$0].isDataOutput && !all[$0].isUserOutput }
                .sorted { all[$0].valueSats > all[$1].valueSats }
                .prefix(Self.maxListedRecipients)
        )
        let listed = all.indices.filter { all[$0].isDataOutput || all[$0].isUserOutput || listedPayers.contains($0) }
        let others = all.indices.filter { !listed.contains($0) }

        self.height = height
        poolTag = coinbase.poolTags.isEmpty ? nil : coinbase.poolTags.joined(separator: " · ")
        signals = []
        self.coin = coin
        isDecoding = true
        outputs = listed.map { all[$0] }
        othersCount = others.count
        othersValueSats = others.reduce(0) { $0 + all[$1].valueSats }
        let total = Double(coinbase.totalSats)
        totalSats = total > 0 ? total : nil
        let user = all.filter(\.isUserOutput).reduce(0) { $0 + $1.valueSats }
        userSats = user

        if all.contains(where: \.isUserOutput) {
            payoutState = .verified
        } else if userScript != nil {
            payoutState = .notFound
        } else {
            payoutState = Self.looksLikeAddress(wallet) ? .unknown : .notApplicable
        }

        // From the pool: a real block has about 13 branches; more than 30 would overflow the shift below.
        let branches = min(max(job.merkleBranchCount, 0), 30)
        transactionRange = branches == 0 ? 1...1 : (1 << (branches - 1)) + 1...(1 << branches)
        self.probedAt = probedAt
    }

    /// Text for one output in the firmware's notation, so `CoinbaseOutput` reads both alike.
    private static func label(for script: [UInt8], coin: MinedCoin) -> String {
        if script.first == 0x6a {
            let payload = script.dropFirst()
            let data: ArraySlice<UInt8>
            switch payload.first {
            case .some(let push) where push >= 0x01 && push <= 0x4b: data = payload.dropFirst()
            case 0x4c: data = payload.dropFirst(2)
            case 0x4d: data = payload.dropFirst(3)
            default: data = payload
            }
            let text = String(data.map { (0x20...0x7e).contains($0) ? Character(UnicodeScalar($0)) : "." })
            return "OP_RETURN: \(text)"
        }
        if let address = CoinAddress.address(for: script, coin: coin) { return address }
        return "UNKNOWN:" + script.map { String(format: "%02x", $0) }.joined()
    }
}
