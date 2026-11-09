import Foundation
import SwiftUI

struct PoolPreset: Identifiable, Sendable, Equatable {
    var id: String { "\(host):\(port)" }
    let name: String
    let category: String
    let host: String
    let port: Int
    let notes: String

    static let commonPools: [PoolPreset] = [
        PoolPreset(
            name: "Public Pool (Solo)",
            category: "Solo Mining",
            host: "public-pool.io",
            port: 21496,
            notes: String(localized: "Popular open-source solo pool for Bitaxe & NerdQAxe++")
        ),
        PoolPreset(
            name: "CKPool EU (Solo)",
            category: "Solo Mining",
            host: "eusolo.ckpool.org",
            port: 3333,
            notes: String(localized: "European CKPool solo server with low latency in central Europe")
        ),
        PoolPreset(
            name: "CKPool Global (Solo)",
            category: "Solo Mining",
            host: "solo.ckpool.org",
            port: 3333,
            notes: String(localized: "Classic global CKPool solo server")
        ),
        PoolPreset(
            name: "AtlasPool EU (Solo)",
            category: "Solo Mining",
            host: "solo.atlaspool.io",
            port: 3333,
            notes: String(localized: "Solo mining pool with low latency")
        ),
        PoolPreset(
            name: "Braiins Pool",
            category: "FPPS / Pool",
            host: "stratum.braiins.com",
            port: 3333,
            notes: String(localized: "Regular payouts (account name.worker required)")
        ),
        PoolPreset(
            name: "OCEAN",
            category: String(localized: "TIDES / Decentralized"),
            host: "mine.ocean.xyz",
            port: 3334,
            notes: String(localized: "Transparent, decentralized Bitcoin pool")
        )
    ]
}

enum LatencyQuality: Sendable {
    case excellent   // < 45 ms
    case good        // 45 - 100 ms
    case fair        // 100 - 200 ms
    case poor        // > 200 ms
    case unavailable

    static func evaluate(_ ms: Double?) -> LatencyQuality {
        guard let ms, ms > 0 else { return .unavailable }
        if ms < 45 { return .excellent }
        if ms < 100 { return .good }
        if ms < 200 { return .fair }
        return .poor
    }

    var label: String {
        switch self {
        case .excellent: return String(localized: "Excellent")
        case .good: return String(localized: "Good")
        case .fair: return String(localized: "Fair")
        case .poor: return String(localized: "High")
        case .unavailable: return String(localized: "No data")
        }
    }

    var color: Color {
        switch self {
        case .excellent, .good: return Signal.good
        case .fair: return Signal.warning
        case .poor: return Signal.bad
        case .unavailable: return Signal.idle
        }
    }
}
