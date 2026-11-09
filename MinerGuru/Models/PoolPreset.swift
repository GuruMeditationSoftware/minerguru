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
            notes: String(localized: "Beliebter Open-Source Solo-Pool für Bitaxe & NerdQAxe++")
        ),
        PoolPreset(
            name: "CKPool EU (Solo)",
            category: "Solo Mining",
            host: "eusolo.ckpool.org",
            port: 3333,
            notes: String(localized: "Europäischer CKPool Solo-Server mit niedriger Latenz in DE/AT/CH")
        ),
        PoolPreset(
            name: "CKPool Global (Solo)",
            category: "Solo Mining",
            host: "solo.ckpool.org",
            port: 3333,
            notes: String(localized: "Klassischer globaler CKPool Solo-Server")
        ),
        PoolPreset(
            name: "AtlasPool EU (Solo)",
            category: "Solo Mining",
            host: "solo.atlaspool.io",
            port: 3333,
            notes: String(localized: "Solo-Mining Pool mit niedriger Latenz")
        ),
        PoolPreset(
            name: "Braiins Pool",
            category: "FPPS / Pool",
            host: "stratum.braiins.com",
            port: 3333,
            notes: String(localized: "Regelmäßige Auszahlungen (Account-Name.Worker erforderlich)")
        ),
        PoolPreset(
            name: "OCEAN",
            category: String(localized: "TIDES / Dezentral"),
            host: "mine.ocean.xyz",
            port: 3334,
            notes: String(localized: "Transparenter, dezentraler Bitcoin-Pool")
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
        case .excellent: return String(localized: "Exzellent")
        case .good: return String(localized: "Gut")
        case .fair: return String(localized: "Mittel")
        case .poor: return String(localized: "Hoch")
        case .unavailable: return String(localized: "Keine Daten")
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
