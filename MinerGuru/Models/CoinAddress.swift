import Foundation
import CryptoKit

/// Converts between addresses and output scripts for the SHA-256 coins MinerGuru knows:
/// Base58 (P2PKH, P2SH), Bech32/Bech32m (SegWit, Taproot) and CashAddr (BCH, eCash).
enum CoinAddress {
    private struct Format {
        let p2pkh: UInt8
        let p2sh: UInt8
        let bech32HRP: String?
        let cashAddrPrefix: String?
    }

    private static func format(for coin: MinedCoin) -> Format {
        switch coin {
        case .bch: return Format(p2pkh: 0x00, p2sh: 0x05, bech32HRP: nil, cashAddrPrefix: "bitcoincash")
        case .xec: return Format(p2pkh: 0x00, p2sh: 0x05, bech32HRP: nil, cashAddrPrefix: "ecash")
        case .bsv: return Format(p2pkh: 0x00, p2sh: 0x05, bech32HRP: nil, cashAddrPrefix: nil)
        case .dgb: return Format(p2pkh: 0x1e, p2sh: 0x3f, bech32HRP: "dgb", cashAddrPrefix: nil)
        case .nmc: return Format(p2pkh: 0x34, p2sh: 0x0d, bech32HRP: "nc", cashAddrPrefix: nil)
        case .ppc: return Format(p2pkh: 0x37, p2sh: 0x75, bech32HRP: "pc", cashAddrPrefix: nil)
        case .btc, .fb, .unknown: return Format(p2pkh: 0x00, p2sh: 0x05, bech32HRP: "bc", cashAddrPrefix: nil)
        }
    }

    // MARK: - Address → script

    /// Output script that pays `address`, independent of the coin: a CashAddr and the legacy address
    /// of the same key give the same script. `nil` for account names and anything unreadable.
    static func scriptPubKey(for address: String) -> [UInt8]? {
        var value = address.trimmingCharacters(in: .whitespaces)
        // Some pools want a mode in front (`solo:<address>` at Kryptex).
        if let colon = value.lastIndex(of: ":"), !value.lowercased().hasPrefix("bitcoincash:"), !value.lowercased().hasPrefix("ecash:") {
            value = String(value[value.index(after: colon)...])
        }
        if let script = cashAddrScript(value) { return script }
        if let script = segwitScript(value) { return script }
        return base58Script(value)
    }

    private static let p2pkhVersions: Set<UInt8> = [0x00, 0x1e, 0x34, 0x37, 0x6f]
    private static let p2shVersions: Set<UInt8> = [0x05, 0x3f, 0x0d, 0x75, 0xc4]

    private static func base58Script(_ address: String) -> [UInt8]? {
        guard let payload = base58CheckDecode(address), payload.count == 21 else { return nil }
        let hash = Array(payload[1...])
        if p2pkhVersions.contains(payload[0]) { return [0x76, 0xa9, 0x14] + hash + [0x88, 0xac] }
        if p2shVersions.contains(payload[0]) { return [0xa9, 0x14] + hash + [0x87] }
        return nil
    }

    private static func segwitScript(_ address: String) -> [UInt8]? {
        guard let (_, version, program) = segwitDecode(address) else { return nil }
        let opcode: UInt8 = version == 0 ? 0x00 : 0x50 + version
        return [opcode, UInt8(program.count)] + program
    }

    private static func cashAddrScript(_ address: String) -> [UInt8]? {
        let lower = address.lowercased()
        let candidates: [(prefix: String, payload: String)]
        if let colon = lower.firstIndex(of: ":") {
            candidates = [(String(lower[..<colon]), String(lower[lower.index(after: colon)...]))]
        } else {
            // Pools accept CashAddr without prefix; the checksum tells which coin it belongs to.
            candidates = ["bitcoincash", "ecash", "bchtest", "ectest"].map { ($0, lower) }
        }
        for candidate in candidates {
            guard let (type, hash) = cashAddrDecode(prefix: candidate.prefix, payload: candidate.payload) else { continue }
            switch type {
            case 0 where hash.count == 20: return [0x76, 0xa9, 0x14] + hash + [0x88, 0xac]
            case 1 where hash.count == 20: return [0xa9, 0x14] + hash + [0x87]
            default: return nil
            }
        }
        return nil
    }

    // MARK: - Script → address

    /// Address an output script pays, in the usual notation of `coin`; `nil` for scripts without one.
    static func address(for script: [UInt8], coin: MinedCoin) -> String? {
        let format = format(for: coin)
        if script.count == 25, script[0] == 0x76, script[1] == 0xa9, script[2] == 0x14, script[23] == 0x88, script[24] == 0xac {
            let hash = Array(script[3..<23])
            if let prefix = format.cashAddrPrefix { return cashAddrEncode(prefix: prefix, type: 0, hash: hash) }
            return base58CheckEncode([format.p2pkh] + hash)
        }
        if script.count == 23, script[0] == 0xa9, script[1] == 0x14, script[22] == 0x87 {
            let hash = Array(script[2..<22])
            if let prefix = format.cashAddrPrefix { return cashAddrEncode(prefix: prefix, type: 1, hash: hash) }
            return base58CheckEncode([format.p2sh] + hash)
        }
        if let hrp = format.bech32HRP, script.count >= 4, Int(script[1]) == script.count - 2,
           script[0] == 0x00 || (0x51...0x60).contains(script[0]) {
            let version: UInt8 = script[0] == 0 ? 0 : script[0] - 0x50
            return segwitEncode(hrp: hrp, version: version, program: Array(script[2...]))
        }
        return nil
    }

    // MARK: - Base58Check

    private static let base58Alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    private static let base58Index: [Character: Int] = Dictionary(
        uniqueKeysWithValues: base58Alphabet.enumerated().map { ($1, $0) }
    )

    private static func doubleSHA256(_ bytes: [UInt8]) -> [UInt8] {
        Array(SHA256.hash(data: Data(SHA256.hash(data: Data(bytes)))))
    }

    static func base58CheckEncode(_ payload: [UInt8]) -> String {
        let bytes = payload + doubleSHA256(payload).prefix(4)
        var digits: [Int] = []
        for byte in bytes {
            var carry = Int(byte)
            for i in digits.indices {
                carry += digits[i] << 8
                digits[i] = carry % 58
                carry /= 58
            }
            while carry > 0 {
                digits.append(carry % 58)
                carry /= 58
            }
        }
        let zeros = bytes.prefix(while: { $0 == 0 }).count
        return String(repeating: "1", count: zeros) + String(digits.reversed().map { base58Alphabet[$0] })
    }

    static func base58CheckDecode(_ string: String) -> [UInt8]? {
        guard !string.isEmpty, string.count <= 64 else { return nil }
        var bytes: [Int] = []
        for char in string {
            guard var carry = base58Index[char] else { return nil }
            for i in bytes.indices {
                carry += bytes[i] * 58
                bytes[i] = carry & 0xff
                carry >>= 8
            }
            while carry > 0 {
                bytes.append(carry & 0xff)
                carry >>= 8
            }
        }
        let zeros = string.prefix(while: { $0 == "1" }).count
        let decoded = [UInt8](repeating: 0, count: zeros) + bytes.reversed().map(UInt8.init)
        guard decoded.count > 4 else { return nil }
        let payload = Array(decoded.dropLast(4))
        guard Array(decoded.suffix(4)) == Array(doubleSHA256(payload).prefix(4)) else { return nil }
        return payload
    }

    // MARK: - Bech32 / Bech32m (BIP 173, BIP 350)

    private static let bech32Charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    private static let bech32Index: [Character: UInt8] = Dictionary(
        uniqueKeysWithValues: bech32Charset.enumerated().map { ($1, UInt8($0)) }
    )
    private static let bech32Constant: UInt32 = 1
    private static let bech32mConstant: UInt32 = 0x2bc8_30a3

    private static func bech32Polymod(_ values: [UInt8]) -> UInt32 {
        let generator: [UInt32] = [0x3b6a_57b2, 0x2650_8e6d, 0x1ea1_19fa, 0x3d42_33dd, 0x2a14_62b3]
        var chk: UInt32 = 1
        for value in values {
            let top = chk >> 25
            chk = (chk & 0x1ff_ffff) << 5 ^ UInt32(value)
            for i in 0..<5 where (top >> i) & 1 == 1 {
                chk ^= generator[i]
            }
        }
        return chk
    }

    private static func hrpExpand(_ hrp: String) -> [UInt8] {
        let scalars = hrp.unicodeScalars.map { UInt8($0.value & 0xff) }
        return scalars.map { $0 >> 5 } + [0] + scalars.map { $0 & 31 }
    }

    private static func segwitEncode(hrp: String, version: UInt8, program: [UInt8]) -> String? {
        guard let converted = convertBits(program, from: 8, to: 5, pad: true) else { return nil }
        let data = [version] + converted
        let constant = version == 0 ? bech32Constant : bech32mConstant
        let polymod = bech32Polymod(hrpExpand(hrp) + data + [0, 0, 0, 0, 0, 0]) ^ constant
        let checksum = (0..<6).map { UInt8((polymod >> (5 * (5 - $0))) & 31) }
        return hrp + "1" + String((data + checksum).map { bech32Charset[Int($0)] })
    }

    private static func segwitDecode(_ address: String) -> (hrp: String, version: UInt8, program: [UInt8])? {
        let lower = address.lowercased()
        guard lower == address || address.uppercased() == address,
              let separator = lower.lastIndex(of: "1"), lower.count <= 90 else { return nil }
        let hrp = String(lower[..<separator])
        let rest = lower[lower.index(after: separator)...]
        guard !hrp.isEmpty, rest.count >= 7 else { return nil }
        var data: [UInt8] = []
        for char in rest {
            guard let value = bech32Index[char] else { return nil }
            data.append(value)
        }
        let polymod = bech32Polymod(hrpExpand(hrp) + data)
        let version = data[0]
        guard version <= 16, polymod == (version == 0 ? bech32Constant : bech32mConstant),
              let program = convertBits(Array(data[1..<(data.count - 6)]), from: 5, to: 8, pad: false),
              (2...40).contains(program.count),
              version != 0 || program.count == 20 || program.count == 32 else { return nil }
        return (hrp, version, program)
    }

    private static func convertBits(_ data: [UInt8], from: Int, to: Int, pad: Bool) -> [UInt8]? {
        var acc = 0
        var bits = 0
        var result: [UInt8] = []
        let maxValue = (1 << to) - 1
        for value in data {
            guard Int(value) >> from == 0 else { return nil }
            acc = (acc << from) | Int(value)
            bits += from
            while bits >= to {
                bits -= to
                result.append(UInt8((acc >> bits) & maxValue))
            }
        }
        if pad {
            if bits > 0 { result.append(UInt8((acc << (to - bits)) & maxValue)) }
        } else if bits >= from || (acc << (to - bits)) & maxValue != 0 {
            return nil
        }
        return result
    }

    // MARK: - CashAddr

    private static func cashAddrPolymod(_ values: [UInt8]) -> UInt64 {
        let generator: [UInt64] = [0x98_f2bc_8e61, 0x79_b76d_99e2, 0xf3_3e5f_b3c4, 0xae_2eab_e2a8, 0x1e_4f43_e470]
        var c: UInt64 = 1
        for value in values {
            let top = UInt8(c >> 35)
            c = (c & 0x07_ffff_ffff) << 5 ^ UInt64(value)
            for i in 0..<5 where (top >> i) & 1 == 1 {
                c ^= generator[i]
            }
        }
        return c ^ 1
    }

    private static func cashAddrPrefixBits(_ prefix: String) -> [UInt8] {
        prefix.unicodeScalars.map { UInt8($0.value & 31) } + [0]
    }

    private static func cashAddrEncode(prefix: String, type: UInt8, hash: [UInt8]) -> String? {
        // Version byte: type in bits 3–6, size code 0 for 160-bit hashes.
        guard let payload = convertBits([type << 3] + hash, from: 8, to: 5, pad: true) else { return nil }
        let polymod = cashAddrPolymod(cashAddrPrefixBits(prefix) + payload + [UInt8](repeating: 0, count: 8))
        let checksum = (0..<8).map { UInt8((polymod >> (5 * (7 - $0))) & 31) }
        return prefix + ":" + String((payload + checksum).map { bech32Charset[Int($0)] })
    }

    private static func cashAddrDecode(prefix: String, payload: String) -> (type: UInt8, hash: [UInt8])? {
        guard payload.count > 8 else { return nil }
        var data: [UInt8] = []
        for char in payload {
            guard let value = bech32Index[char] else { return nil }
            data.append(value)
        }
        guard cashAddrPolymod(cashAddrPrefixBits(prefix) + data) == 0,
              let bytes = convertBits(Array(data.dropLast(8)), from: 5, to: 8, pad: false),
              let version = bytes.first else { return nil }
        return (version >> 3, Array(bytes.dropFirst()))
    }
}
