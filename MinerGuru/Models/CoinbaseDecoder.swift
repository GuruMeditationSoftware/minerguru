import Foundation

/// The coinbase transaction of a Stratum job, taken apart: height, pool tag and outputs.
struct DecodedCoinbase: Equatable, Sendable {
    struct Output: Equatable, Sendable {
        var valueSats: UInt64
        var script: [UInt8]

        var isDataOutput: Bool { script.first == 0x6a }
    }

    /// BIP34 height from the start of the scriptSig.
    var height: Int?
    var scriptSig: [UInt8]
    var outputs: [Output]

    var totalSats: UInt64 { outputs.reduce(0) { $0 + $1.valueSats } }

    /// Readable parts of the scriptSig after the height, e.g. `/solo.ckpool.org/`.
    var poolTags: [String] {
        let start = scriptSig.first.map { Int($0) + 1 } ?? 0
        guard start < scriptSig.count else { return [] }
        var tags: [String] = []
        var run: [UInt8] = []
        for byte in scriptSig[start...] {
            if (0x20...0x7e).contains(byte) {
                run.append(byte)
            } else {
                if run.count >= 4 { tags.append(String(decoding: run, as: UTF8.self)) }
                run = []
            }
        }
        if run.count >= 4 { tags.append(String(decoding: run, as: UTF8.self)) }
        return tags.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

/// Builds the coinbase from `mining.notify` the way a miner does and parses it.
enum CoinbaseDecoder {
    /// `coinb1 + extranonce1 + extranonce2 + coinb2` with a zero extranonce2. Without a usable
    /// extranonce (pools that refuse the subscribe still send work), the gap is found by trying
    /// every length until the transaction parses to its last byte.
    static func decode(coinb1: String, coinb2: String, extranonce1: String?, extranonce2Size: Int?) -> DecodedCoinbase? {
        guard let head = bytes(fromHex: coinb1), let tail = bytes(fromHex: coinb2) else { return nil }
        if let extranonce1, let extranonce2Size, let nonce1 = bytes(fromHex: extranonce1), (0...32).contains(extranonce2Size),
           let decoded = parse(head + nonce1 + [UInt8](repeating: 0, count: extranonce2Size) + tail) {
            return decoded
        }
        for gap in 0...32 {
            if let decoded = parse(head + [UInt8](repeating: 0, count: gap) + tail) { return decoded }
        }
        return nil
    }

    /// Parses a legacy (non-witness) transaction with one input; `nil` unless every byte is used.
    static func parse(_ tx: [UInt8]) -> DecodedCoinbase? {
        var reader = ByteReader(tx)
        guard reader.skip(4),
              reader.varInt() == 1,
              reader.skip(36),
              let scriptLength = reader.varInt(), scriptLength <= 100,
              let scriptSig = reader.read(Int(scriptLength)),
              reader.skip(4),
              let outputCount = reader.varInt(), (1...1000).contains(outputCount) else { return nil }
        var outputs: [DecodedCoinbase.Output] = []
        for _ in 0..<outputCount {
            guard let value = reader.uint64(),
                  let length = reader.varInt(), length <= 10_000,
                  let script = reader.read(Int(length)) else { return nil }
            outputs.append(.init(valueSats: value, script: script))
        }
        guard reader.skip(4), reader.isAtEnd else { return nil }
        return DecodedCoinbase(height: bip34Height(scriptSig), scriptSig: scriptSig, outputs: outputs)
    }

    private static func bip34Height(_ scriptSig: [UInt8]) -> Int? {
        guard let length = scriptSig.first.map(Int.init), (1...8).contains(length), scriptSig.count > length else { return nil }
        return scriptSig[1...length].reversed().reduce(0) { $0 << 8 | Int($1) }
    }

    static func bytes(fromHex hex: String) -> [UInt8]? {
        let chars = Array(hex.utf8)
        guard chars.count.isMultiple(of: 2) else { return nil }
        var result: [UInt8] = []
        result.reserveCapacity(chars.count / 2)
        var index = 0
        while index < chars.count {
            guard let high = hexValue(chars[index]), let low = hexValue(chars[index + 1]) else { return nil }
            result.append(high << 4 | low)
            index += 2
        }
        return result
    }

    private static func hexValue(_ char: UInt8) -> UInt8? {
        switch char {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return char - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return char - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return char - UInt8(ascii: "A") + 10
        default: return nil
        }
    }
}

private struct ByteReader {
    private let bytes: [UInt8]
    private var offset = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var isAtEnd: Bool { offset == bytes.count }

    mutating func skip(_ count: Int) -> Bool { read(count) != nil }

    mutating func read(_ count: Int) -> [UInt8]? {
        guard count >= 0, offset + count <= bytes.count else { return nil }
        defer { offset += count }
        return Array(bytes[offset..<(offset + count)])
    }

    mutating func uint64() -> UInt64? {
        read(8)?.reversed().reduce(0) { $0 << 8 | UInt64($1) }
    }

    mutating func varInt() -> UInt64? {
        guard let first = read(1)?.first else { return nil }
        let width: Int
        switch first {
        case 0xfd: width = 2
        case 0xfe: width = 4
        case 0xff: width = 8
        default: return UInt64(first)
        }
        return read(width)?.reversed().reduce(0) { $0 << 8 | UInt64($1) }
    }
}
