import Foundation

/// How the payout address of a pool slot looks.
enum PayoutVerdict: String, Equatable, Sendable {
    /// The address the user set for this coin.
    case expected
    /// A valid address, and no expected address is set for the coin.
    case valid
    /// A valid address that is not the expected one.
    case foreign
    /// The firmware's placeholder or a default that pays someone else.
    case factoryDefault
    /// No valid address: an account name at a pool, or a typing error.
    case account
    case empty

    var needsAttention: Bool { self == .foreign || self == .factoryDefault }
}

/// One configured pool slot and whom it pays.
struct PayoutSlot: Equatable, Identifiable, Sendable {
    let key: String
    let title: String
    let host: String
    let user: String
    let address: String
    let coin: MinedCoin
    let verdict: PayoutVerdict

    var id: String { key }
}

/// Checks the payout addresses of a miner. Only reads: MinerGuru never changes an address by itself.
enum PayoutCheck {
    /// Shipped defaults of the firmwares: `replace-this-with-your-btc-address` on AxeOS,
    /// and on NerdOS a real address of somebody else.
    static let knownDefaults: Set<String> = ["bc1q7n70rumyv6lvu8avpml0c3uggvssfu52egum3q"]
    private static let placeholders = ["replace-this", "your-btc-address", "yourbtcaddress", "your_btc_address"]

    /// The part of a Stratum user in front of the first dot.
    static func address(fromUser user: String) -> String {
        let trimmed = user.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.firstIndex(of: ".").map { String(trimmed[..<$0]) } ?? trimmed
    }

    static func verdict(user: String, expected: String?) -> PayoutVerdict {
        let address = address(fromUser: user)
        let lower = address.lowercased()
        if address.isEmpty { return .empty }
        if knownDefaults.contains(lower) || placeholders.contains(where: { lower.contains($0) }) { return .factoryDefault }
        guard let script = CoinAddress.scriptPubKey(for: address) else {
            if let expected, !expected.isEmpty, lower == expected.lowercased() { return .expected }
            return .account
        }
        // A half-typed expected address is no target yet.
        guard let expected, let target = CoinAddress.scriptPubKey(for: expected) else { return .valid }
        return target == script ? .expected : .foreign
    }

    /// All slots with something configured: AxeOS 2.15+ lists up to eight, others primary and fallback.
    static func slots(of info: MinerSystemInfo, expected: [String: String]) -> [PayoutSlot] {
        func slot(_ key: String, _ title: String, host: String, user: String) -> PayoutSlot? {
            guard !host.isEmpty || !user.isEmpty else { return nil }
            let coin = MinedCoin.detect(poolHost: host, stratumUser: user)
            return PayoutSlot(
                key: key, title: title, host: host, user: user, address: address(fromUser: user), coin: coin,
                verdict: verdict(user: user, expected: expected[coin.rawValue])
            )
        }
        if let pools = info.axePools, !pools.isEmpty {
            return pools.compactMap { slot("pool\($0.id)", "Pool \($0.id + 1)", host: $0.stratumURL, user: $0.stratumUser) }
        }
        return [
            slot("primary", String(localized: "Primär"), host: info.stratumURL, user: info.stratumUser),
            slot("fallback", String(localized: "Fallback"), host: info.fallbackStratumURL, user: info.fallbackStratumUser),
        ].compactMap { $0 }
    }

    /// `worker` of the slot's user stays, the address in front of it changes.
    static func user(_ user: String, withAddress address: String) -> String {
        let trimmed = user.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.firstIndex(of: ".").map { address + trimmed[$0...] } ?? address
    }

    /// Only solo pools pay the block to the miner's own address; shared pools and donation
    /// pools show `not_found` by design.
    static func isSoloPool(host: String, user: String) -> Bool {
        let host = host.lowercased()
        return host.contains("solo") || host.contains("ckpool") || host.contains("public-pool") || user.lowercased().hasPrefix("solo:")
    }

    /// The firmware says the block it works on does not pay the miner.
    static func blockSkipsMiner(_ info: MinerSystemInfo) -> Bool {
        info.coinbasePayoutStatus == "not_found"
            && !info.isDualPoolMining
            && info.activePoolCoin == .btc
            && isSoloPool(host: info.activePoolHost, user: info.activePoolUser)
    }

    /// Short form for notifications.
    static func shortened(_ address: String) -> String {
        address.count > 14 ? "\(address.prefix(6))…\(address.suffix(5))" : address
    }
}

/// What was last seen in each slot, kept across launches to notice changes made elsewhere.
struct PayoutMemory: Codable, Equatable, Sendable {
    var seen: [String: [String: String]] = [:]
    var alerted: [String: [String: String]] = [:]
}
