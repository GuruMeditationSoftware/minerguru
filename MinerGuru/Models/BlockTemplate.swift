import Foundation

/// One output of the coinbase transaction the miner is hashing on (`coinbaseOutputs[]`, AxeOS 2.13+).
struct CoinbaseOutput: Codable, Sendable, Equatable {
    var valueSats: Double
    /// Address decoded by the firmware, `OP_RETURN: <text>` for data outputs, `UNKNOWN:<hex>` otherwise.
    var address: String
    /// The firmware matched the scriptPubKey against the address in the Stratum user.
    var isUserOutput: Bool

    init(valueSats: Double, address: String, isUserOutput: Bool = false) {
        self.valueSats = valueSats
        self.address = address
        self.isUserOutput = isUserOutput
    }

    /// Data output without value, e.g. the SegWit witness commitment or a merge-mining tag.
    var isDataOutput: Bool { address.hasPrefix("OP_RETURN") }

    /// Payload of a data output as the firmware prints it (non-printable bytes come as `.`).
    private var dataPayload: Substring {
        address.dropFirst("OP_RETURN".count).drop(while: { $0 == ":" || $0 == " " })
    }

    /// SegWit witness commitment: payload starts with `aa21a9ed`, printed as `.!..`.
    var isWitnessCommitment: Bool { isDataOutput && dataPayload.hasPrefix(".!..") }

    /// Readable text of a data output (pool or merge-mining tag), `nil` for binary data.
    var dataText: String? {
        guard isDataOutput, !isWitnessCommitment else { return nil }
        let payload = dataPayload
        let readable = payload.filter { $0 != "." }.count
        return payload.count >= 3 && Double(readable) >= Double(payload.count) * 0.6 ? String(payload) : nil
    }

    private enum CodingKeys: String, CodingKey {
        case value, address, isUserOutput
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        valueSats = (try? c.decode(Double.self, forKey: .value)) ?? 0
        address = (try? c.decode(String.self, forKey: .address)) ?? ""
        isUserOutput = (try? c.decode(Bool.self, forKey: .isUserOutput))
            ?? ((try? c.decode(Int.self, forKey: .isUserOutput)).map { $0 != 0 } ?? false)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(valueSats, forKey: .value)
        try c.encode(address, forKey: .address)
        try c.encode(isUserOutput ? 1 : 0, forKey: .isUserOutput)
    }
}

/// What the miner knows about the block it is hashing on right now: the pool's template as seen
/// through the coinbase (height, pool tag, payout). The transaction list itself never reaches the miner.
struct BlockTemplateSummary: Equatable {
    enum PayoutState: Equatable {
        /// The coinbase pays the address from the Stratum user.
        case verified
        /// Address in the Stratum user, but no output pays it.
        case notFound
        /// No address in the Stratum user (account pool), nothing to check.
        case notApplicable
        /// Coinbase decoding is switched off for the active pool.
        case decodingOff
        case unknown
    }

    let height: Int
    let poolTag: String?
    let signals: [String]
    let coin: MinedCoin
    /// Coinbase decoding of the active pool slot; `nil` if the firmware does not say.
    let isDecoding: Bool?
    let outputs: [CoinbaseOutput]
    let othersCount: Int
    let othersValueSats: Double
    /// Sum of all outputs (subsidy + fees); `nil` if missing or implausible.
    let totalSats: Double?
    let userSats: Double?
    let payoutState: PayoutState
    /// Transactions in the template, from the merkle branch count; only known from a Stratum probe.
    var transactionRange: ClosedRange<Int>? = nil
    /// Set when MinerGuru read the template from the pool itself instead of the miner reporting it.
    var probedAt: Date? = nil

    /// `nil` if the firmware reports no block data (NerdOS, AxeOS < 2.13, Stratum V2 standard jobs).
    init?(info: MinerSystemInfo) {
        guard let height = info.blockHeight, height > 0 else { return nil }
        self.height = height
        coin = info.activePoolCoin
        signals = info.blockSignals ?? []

        let tag = info.blockScriptSig?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        poolTag = tag.isEmpty || tag.hasPrefix("[") ? nil : tag

        isDecoding = info.activePoolDecodesCoinbase
        outputs = isDecoding == false ? [] : (info.coinbaseOutputs ?? [])
        othersCount = info.coinbaseOthersCount ?? 0
        othersValueSats = info.coinbaseOthersValueSats ?? 0

        let maxSats = Self.maxPlausibleSats(for: coin)
        if let total = info.coinbaseValueTotalSats, total > 0, total <= maxSats {
            totalSats = total
        } else {
            totalSats = nil
        }
        let user = info.coinbaseValueUserSats ?? outputs.filter(\.isUserOutput).reduce(0) { $0 + $1.valueSats }
        userSats = isDecoding == false || totalSats == nil ? nil : min(user, totalSats ?? user)

        payoutState = Self.payoutState(
            reported: info.coinbasePayoutStatus,
            isDecoding: isDecoding,
            outputs: outputs,
            userSats: userSats,
            stratumUser: info.isUsingFallbackStratum ? info.fallbackStratumUser : info.stratumUser
        )
    }

    /// New coins the block creates, from height and coin; `nil` for coins with another schedule.
    var subsidySats: Double? { Self.subsidySats(height: height, coin: coin) }

    /// Fees of the transactions in the template: total minus subsidy.
    var feesSats: Double? {
        guard let totalSats, let subsidySats, totalSats >= subsidySats else { return nil }
        return totalSats - subsidySats
    }

    /// Share of the block reward that goes to the own address (0…1).
    var userShare: Double? {
        guard let userSats, let totalSats, totalSats > 0 else { return nil }
        return userSats / totalSats
    }

    // MARK: - Rules

    /// Bitcoin-style halving schedule: 50 coins, halved every 210,000 blocks.
    static func subsidySats(height: Int, coin: MinedCoin) -> Double? {
        switch coin {
        case .btc, .bch, .bsv, .xec:
            let halvings = height / 210_000
            guard halvings < 64 else { return 0 }
            return Double(5_000_000_000 >> halvings)
        default:
            return nil
        }
    }

    /// Whole supply as upper bound: the firmware reports leftovers when it never decoded a job.
    private static func maxPlausibleSats(for coin: MinedCoin) -> Double {
        coin == .dgb ? 21e9 * 1e8 : 21e6 * 1e8
    }

    static func payoutState(
        reported: String?,
        isDecoding: Bool?,
        outputs: [CoinbaseOutput],
        userSats: Double?,
        stratumUser: String
    ) -> PayoutState {
        switch reported?.lowercased() {
        case "verified": return .verified
        case "not_found": return .notFound
        case "not_applicable": return .notApplicable
        default: break
        }
        // AxeOS < 2.16 has no status: derive it the way the firmware does.
        if isDecoding == false { return .decodingOff }
        guard !outputs.isEmpty else { return .unknown }
        if outputs.contains(where: \.isUserOutput) || (userSats ?? 0) > 0 { return .verified }
        let wallet = stratumUser.split(separator: ".", maxSplits: 1).first.map(String.init) ?? ""
        return looksLikeAddress(wallet) ? .notFound : .notApplicable
    }

    /// Rough format check for the wallet part of a Stratum user; account names fail it.
    static func looksLikeAddress(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespaces)
        let lower = value.lowercased()
        let bech32Prefixes = ["bc1", "tb1", "bcrt1", "dgb1", "bitcoincash:", "ecash:", "bchtest:"]
        if bech32Prefixes.contains(where: lower.hasPrefix) { return value.count >= 26 }
        let base58 = CharacterSet(charactersIn: "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        if (25...35).contains(value.count), value.unicodeScalars.allSatisfy(base58.contains) { return true }
        // CashAddr without prefix
        if value.count == 42, lower.hasPrefix("q") || lower.hasPrefix("p") { return true }
        return false
    }

    // MARK: - Formatting

    /// Amount in whole coins with all decimals, e.g. `3,12841234 BTC`.
    static func formatCoins(_ sats: Double, coin: MinedCoin) -> String {
        let decimals = coin == .xec ? 2 : 8
        let divisor = coin == .xec ? 100.0 : 100_000_000.0
        let amount = (sats / divisor).formatted(.number.precision(.fractionLength(decimals)))
        return "\(amount) \(coin.symbol)"
    }
}

extension MinerSystemInfo {
    /// `stratumDecodeCoinbase` of the slot that delivers the current job; the firmware default is on.
    var activePoolDecodesCoinbase: Bool? {
        let slotIndex = isUsingFallbackStratum ? secondaryPoolIndex : primaryPoolIndex
        if let slotIndex, let slot = axePools?.first(where: { $0.id == slotIndex }), let decode = slot.stratumDecodeCoinbase {
            return decode
        }
        return isUsingFallbackStratum ? fallbackStratumDecodeCoinbase : stratumDecodeCoinbase
    }
}
