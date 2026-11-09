import Foundation

/// Represents the SHA-256 cryptocurrency detected for a Stratum pool slot based on pool host, wallet format, and network difficulty.
enum MinedCoin: String, Codable, Sendable, Equatable, CaseIterable {
    case btc = "BTC"
    case bch = "BCH"
    case dgb = "DGB"
    case xec = "XEC"
    case bsv = "BSV"
    case ppc = "PPC"
    case nmc = "NMC"
    case fb  = "FB"
    case unknown = "SHA-256"

    var symbol: String { rawValue }

    var fullName: String {
        switch self {
        case .btc: return "Bitcoin"
        case .bch: return "Bitcoin Cash"
        case .dgb: return "DigiByte"
        case .xec: return "eCash"
        case .bsv: return "Bitcoin SV"
        case .ppc: return "Peercoin"
        case .nmc: return "Namecoin"
        case .fb:  return "Fractal Bitcoin"
        case .unknown: return "SHA-256 Coin"
        }
    }

    var systemImage: String {
        switch self {
        case .btc, .bch: return "bitcoinsign.circle.fill"
        case .dgb: return "d.circle.fill"
        case .xec: return "e.circle.fill"
        case .bsv: return "b.circle.fill"
        case .ppc: return "p.circle.fill"
        case .nmc: return "n.circle.fill"
        case .fb:  return "f.circle.fill"
        case .unknown: return "circle.hexagongrid.fill"
        }
    }

    /// Explicit coin indicators in the pool hostname.
    private static func fromHost(_ host: String) -> MinedCoin? {
        if host.hasPrefix("bch.") || host.contains(".bch.") || host.contains("-bch") || host.contains("bchpool") || host.contains("bitcoincash") {
            return .bch
        }
        if host.contains("digibyte") || host.hasPrefix("dgb.") || host.contains(".dgb.") || host.contains("-dgb") {
            return .dgb
        }
        if host.contains("ecash") || host.hasPrefix("xec.") || host.contains(".xec.") || host.contains("-xec") {
            return .xec
        }
        if host.hasPrefix("bsv.") || host.contains(".bsv.") || host.contains("bitcoinsv") {
            return .bsv
        }
        if host.contains("peercoin") || host.hasPrefix("ppc.") || host.contains(".ppc.") {
            return .ppc
        }
        if host.contains("namecoin") || host.hasPrefix("nmc.") || host.contains(".nmc.") {
            return .nmc
        }
        if host.contains("fractal") || host.hasPrefix("fb.") || host.contains(".fb.") {
            return .fb
        }
        return nil
    }

    /// Wallet address prefix / format.
    private static func fromAddress(_ wallet: String) -> MinedCoin? {
        let lower = wallet.lowercased()
        if lower.hasPrefix("bitcoincash:") {
            return .bch
        }
        if lower.hasPrefix("ecash:") {
            return .xec
        }
        if lower.hasPrefix("dgb1") {
            return .dgb
        }
        if lower.hasPrefix("bc1q") || lower.hasPrefix("bc1p") {
            return .btc
        }
        if lower.hasPrefix("pc1") {
            return .ppc
        }
        if lower.hasPrefix("nc1") {
            return .nmc
        }

        // CashAddr without `bitcoincash:` prefix: starts with `q` or `p`, 42 chars, Bech32 charset
        let cashAddrCharset = Set("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
        if (wallet.hasPrefix("q") || wallet.hasPrefix("p"))
            && wallet.count == 42
            && wallet.allSatisfy({ cashAddrCharset.contains($0) }) {
            return .bch
        }

        // DigiByte Legacy address (`D...` or `S...`)
        if wallet.hasPrefix("D") && (26...35).contains(wallet.count) {
            return .dgb
        }
        return nil
    }

    /// Pools known to mine Bitcoin only, which their hostname does not say.
    private static let bitcoinHosts = ["ckpool.org", "public-pool.io", "atlaspool.io", "braiins.com", "ocean.xyz"]

    /// The coins of pool and address when they clearly differ. Payouts to such an address may be lost, but a
    /// multi-coin pool can still be right, so this only warns. Legacy addresses fit several coins and never count.
    static func mismatch(poolHost: String, stratumUser: String) -> (pool: MinedCoin, address: MinedCoin)? {
        let host = StratumHost.clean(poolHost).lowercased()
        let wallet = stratumUser.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".").first.map(String.init) ?? ""
        let isBitcoinHost = bitcoinHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
        guard let pool = fromHost(host) ?? (isBitcoinHost ? .btc : nil),
              let address = fromAddress(wallet), pool != address else { return nil }
        return (pool, address)
    }

    /// Detects the SHA-256 coin being mined on a pool slot using 3 signals:
    /// 1) Pool hostname keywords (`bch.`, `dgb`, `xec`, etc.)
    /// 2) Wallet address prefix / encoding (`bc1q`/`bc1p`, `bitcoincash:` / 42-char CashAddr `q...`, `ecash:`, `dgb1...`)
    /// 3) Live blockchain `networkDifficulty` reported by Stratum (`>20T` = BTC, `50G..10T` = BCH, `1M..50G` = DGB)
    static func detect(poolHost: String, stratumUser: String, networkDifficulty: Double? = nil) -> MinedCoin {
        let host = poolHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rawUser = stratumUser.trimmingCharacters(in: .whitespacesAndNewlines)

        if host.isEmpty && rawUser.isEmpty {
            return .unknown
        }

        // Extract wallet address before optional `.worker` suffix (keep `prefix:addr` intact if present)
        let wallet: String = {
            if let dotIdx = rawUser.firstIndex(of: ".") {
                return String(rawUser[..<dotIdx])
            }
            return rawUser
        }()
        let walletLower = wallet.lowercased()

        if let coin = fromHost(host) { return coin }
        if let coin = fromAddress(wallet) { return coin }

        // 3. Blockchain Network Difficulty heuristic (when reported by Stratum)
        if let netDiff = networkDifficulty, netDiff > 0 {
            if netDiff >= 20_000_000_000_000 {
                return .btc // BTC network diff is ~100T–150T+
            }
            if netDiff >= 50_000_000_000 && netDiff < 10_000_000_000_000 {
                return .bch // BCH network diff is ~400G–1.5T
            }
            if netDiff >= 1_000_000 && netDiff < 50_000_000_000 {
                return .dgb // DGB SHA-256 diff is in the M–G range
            }
        }

        // 4. Known Bitcoin solo / mining pools & legacy BTC addresses (`1...` / `3...`)
        let knownBTCHosts = [
            "ckpool.org", "public-pool.io", "ocean.xyz", "braiins.com",
            "slushpool.com", "kano.is", "vkbit.com", "antpool.com",
            "f2pool.com", "viabtc.com", "foundryusa.com", "luxor.tech", "btc."
        ]
        if knownBTCHosts.contains(where: { host.contains($0) }) {
            return .btc
        }

        if (wallet.hasPrefix("1") || wallet.hasPrefix("3")) && (26...35).contains(wallet.count) {
            return .btc
        }

        return .unknown
    }
}
