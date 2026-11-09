import Foundation

/// One pool slot of AxeOS 2.15+ (`pools[]` in `/api/system/info` and `PATCH /api/system`).
///
/// The firmware rebuilds a slot from scratch on every write and resets fields that are not sent,
/// so the advanced settings read from the miner (TLS, SV2, difficulty, …) are written back unchanged.
struct AxeOSPool: Codable, Sendable, Equatable {
    /// Slot index on the miner (`0..<AxeOSPool.slotCount`).
    var id: Int
    var stratumURL: String
    var stratumPort: Int
    var stratumUser: String
    /// The firmware reports `*****`; sending that value back keeps the stored password.
    var stratumPassword: String?
    var stratumProtocol: String?
    var stratumSuggestedDifficulty: Double?
    var stratumExtranonceSubscribe: Bool?
    var stratumTLS: Int?
    var stratumCert: String?
    var stratumDecodeCoinbase: Bool?
    var stratumShareWarning: Bool?
    var stratumV2ChannelType: String?
    var stratumV2AuthorityPubkey: String?
    var stratumV2RequireAuth: Bool?

    /// `MAX_POOLS` in ESP-Miner.
    static let slotCount = 8
    /// Placeholder the firmware returns instead of the real password.
    static let maskedPassword = "*****"

    init(
        id: Int,
        stratumURL: String,
        stratumPort: Int,
        stratumUser: String,
        stratumPassword: String? = nil,
        stratumProtocol: String? = nil,
        stratumSuggestedDifficulty: Double? = nil,
        stratumExtranonceSubscribe: Bool? = nil,
        stratumTLS: Int? = nil,
        stratumCert: String? = nil,
        stratumDecodeCoinbase: Bool? = nil,
        stratumShareWarning: Bool? = nil,
        stratumV2ChannelType: String? = nil,
        stratumV2AuthorityPubkey: String? = nil,
        stratumV2RequireAuth: Bool? = nil
    ) {
        self.id = id
        self.stratumURL = stratumURL
        self.stratumPort = stratumPort
        self.stratumUser = stratumUser
        self.stratumPassword = stratumPassword
        self.stratumProtocol = stratumProtocol
        self.stratumSuggestedDifficulty = stratumSuggestedDifficulty
        self.stratumExtranonceSubscribe = stratumExtranonceSubscribe
        self.stratumTLS = stratumTLS
        self.stratumCert = stratumCert
        self.stratumDecodeCoinbase = stratumDecodeCoinbase
        self.stratumShareWarning = stratumShareWarning
        self.stratumV2ChannelType = stratumV2ChannelType
        self.stratumV2AuthorityPubkey = stratumV2AuthorityPubkey
        self.stratumV2RequireAuth = stratumV2RequireAuth
    }

    private enum CodingKeys: String, CodingKey {
        case id, stratumURL, stratumPort, stratumUser, stratumPassword, stratumProtocol
        case stratumSuggestedDifficulty, stratumExtranonceSubscribe, stratumTLS, stratumCert
        case stratumDecodeCoinbase, stratumShareWarning
        case stratumV2ChannelType, stratumV2AuthorityPubkey, stratumV2RequireAuth
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func int(_ key: CodingKeys) -> Int? {
            (try? c.decode(Int.self, forKey: key)) ?? (try? c.decode(Double.self, forKey: key)).map { Int($0) }
        }
        func bool(_ key: CodingKeys) -> Bool? {
            (try? c.decode(Bool.self, forKey: key)) ?? int(key).map { $0 != 0 }
        }
        guard let id = int(.id) else {
            throw DecodingError.keyNotFound(CodingKeys.id, .init(codingPath: c.codingPath, debugDescription: "Pool slot without id"))
        }
        self.id = id
        stratumURL = (try? c.decode(String.self, forKey: .stratumURL)) ?? ""
        stratumPort = int(.stratumPort) ?? 3333
        stratumUser = (try? c.decode(String.self, forKey: .stratumUser)) ?? ""
        stratumPassword = try? c.decode(String.self, forKey: .stratumPassword)
        stratumProtocol = try? c.decode(String.self, forKey: .stratumProtocol)
        stratumSuggestedDifficulty = (try? c.decode(Double.self, forKey: .stratumSuggestedDifficulty))
        stratumExtranonceSubscribe = bool(.stratumExtranonceSubscribe)
        // `/api/system/info` reports TLS as a number in `pools[]` but as a bool at top level.
        stratumTLS = int(.stratumTLS) ?? (try? c.decode(Bool.self, forKey: .stratumTLS)).map { $0 ? 1 : 0 }
        stratumCert = try? c.decode(String.self, forKey: .stratumCert)
        stratumDecodeCoinbase = bool(.stratumDecodeCoinbase)
        stratumShareWarning = bool(.stratumShareWarning)
        stratumV2ChannelType = try? c.decode(String.self, forKey: .stratumV2ChannelType)
        stratumV2AuthorityPubkey = try? c.decode(String.self, forKey: .stratumV2AuthorityPubkey)
        stratumV2RequireAuth = bool(.stratumV2RequireAuth)
    }
}

/// Decodes one `pools[]` element without failing the whole array on a malformed slot.
struct LenientAxeOSPool: Decodable {
    let pool: AxeOSPool?

    init(from decoder: Decoder) throws {
        pool = try? AxeOSPool(from: decoder)
    }
}
