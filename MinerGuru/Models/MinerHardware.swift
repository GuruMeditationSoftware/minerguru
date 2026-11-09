import Foundation

/// Firmware family of a miner. Decides which API fields exist and how settings are written.
enum MinerFirmware: String, Codable, Sendable {
    /// ESP-Miner / AxeOS (all Bitaxe boards). Always reports `boardVersion`.
    case axeOS
    /// ESP-Miner-NerdQAxePlus / NerdOS (NerdAxe, NerdQAxe, NerdOCTAXE, …). Reports `deviceModel`, no `boardVersion`.
    case nerdOS
}

/// Bitaxe board families from ESP-Miner's `device_config.h` (`default_configs[]`).
/// Board versions of a family share a number range, so new revisions are recognised too.
struct BitaxeFamily: Equatable, Sendable {
    let name: String
    let asicCount: Int
    /// Clock tuning differs from the plain ASIC defaults on some boards.
    let tuning: AsicTuning?

    static let max        = BitaxeFamily(name: "Bitaxe Max", asicCount: 1, tuning: nil)
    static let ultra      = BitaxeFamily(name: "Bitaxe Ultra", asicCount: 1, tuning: nil)
    static let hex        = BitaxeFamily(name: "Bitaxe Hex", asicCount: 6, tuning: nil)
    static let supra      = BitaxeFamily(name: "Bitaxe Supra", asicCount: 1, tuning: nil)
    static let gamma      = BitaxeFamily(name: "Bitaxe Gamma", asicCount: 1, tuning: nil)
    static let gammaDuo   = BitaxeFamily(name: "Bitaxe Gamma Duo", asicCount: 2, tuning: .bm1370XP)
    static let supraHex   = BitaxeFamily(name: "Bitaxe Supra Hex", asicCount: 6, tuning: nil)
    static let gammaTurbo = BitaxeFamily(name: "Bitaxe GT", asicCount: 2, tuning: nil)
    static let najaDuo    = BitaxeFamily(name: "Bitaxe Naja Duo", asicCount: 2, tuning: nil)
    static let gammaHex   = BitaxeFamily(name: "Bitaxe Gamma Hex", asicCount: 6, tuning: .bm1370Hex)

    /// Family for an AxeOS `boardVersion` such as `"601"`, `"302"` or the early `"2.2"` / `"0.11"`.
    static func forBoard(_ boardVersion: String) -> BitaxeFamily? {
        switch boardVersion.trimmingCharacters(in: .whitespaces) {
        case "2.2": return .max
        case "0.11": return .ultra
        default: break
        }
        guard let number = Int(boardVersion.trimmingCharacters(in: .whitespaces)) else { return nil }
        switch number {
        case 100..<200:   return .max
        case 200..<300:   return .ultra
        case 300..<400:   return .hex
        case 400..<500:   return .supra
        case 600..<650:   return .gamma
        case 650..<700:   return .gammaDuo
        case 700..<800:   return .supraHex
        case 800..<900:   return .gammaTurbo
        case 1200..<1300: return .najaDuo
        case 1300..<1400: return .gammaHex
        default:          return nil
        }
    }
}

/// NerdOS boards from ESP-Miner-NerdQAxePlus `main/boards/*.cpp` (`m_deviceModel`, `m_asicCount`).
/// Older NerdOS versions spelled the name differently (`NerdQAxePlusPlus`) and did not report the chip count.
struct NerdOSModel: Equatable, Sendable {
    let name: String
    let asicCount: Int

    /// Matched against the lowercased `deviceModel`, most specific first.
    private static let table: [(prefixes: [String], model: NerdOSModel)] = [
        (["nerdqaxeplusplus", "nerdqaxe++"], NerdOSModel(name: "NerdQAxe++", asicCount: 4)),
        (["nerdqaxeplus", "nerdqaxe+"], NerdOSModel(name: "NerdQAxe+", asicCount: 4)),
        (["nerdoctaxe"], NerdOSModel(name: "", asicCount: 8)),
        (["nerdhaxe"], NerdOSModel(name: "", asicCount: 6)),
        (["nerdeko"], NerdOSModel(name: "", asicCount: 12)),
        (["nerdqx", "q1370", "q1373", "nerdqaxe"], NerdOSModel(name: "", asicCount: 4)),
        (["nerdaxe"], NerdOSModel(name: "", asicCount: 1)),
    ]

    /// Known model for a reported `deviceModel`; an empty `name` keeps the reported spelling.
    static func forDeviceModel(_ deviceModel: String) -> NerdOSModel? {
        let lower = deviceModel.lowercased().trimmingCharacters(in: .whitespaces)
        return table.first { entry in entry.prefixes.contains { lower.hasPrefix($0) } }?.model
    }
}

/// Factory clock settings and the steps the firmware offers for one ASIC configuration
/// (ESP-Miner `AsicConfig`: `default_frequency_mhz`, `frequency_options`, `voltage_options`).
struct AsicTuning: Equatable, Sendable {
    let defaultFrequencyMHz: Int
    let defaultVoltageMV: Int
    let frequencyOptions: [Int]
    let voltageOptions: [Int]

    static let bm1397 = AsicTuning(defaultFrequencyMHz: 425, defaultVoltageMV: 1400,
                                   frequencyOptions: [400, 425, 450, 475, 485, 500, 525, 550, 575, 600],
                                   voltageOptions: [1100, 1150, 1200, 1250, 1300, 1350, 1400, 1450, 1500])
    static let bm1366 = AsicTuning(defaultFrequencyMHz: 485, defaultVoltageMV: 1200,
                                   frequencyOptions: [400, 425, 450, 475, 485, 500, 525, 550, 575],
                                   voltageOptions: [1100, 1150, 1200, 1250, 1300])
    static let bm1368 = AsicTuning(defaultFrequencyMHz: 490, defaultVoltageMV: 1166,
                                   frequencyOptions: [400, 425, 450, 475, 485, 490, 500, 525, 550, 575],
                                   voltageOptions: [1100, 1150, 1166, 1200, 1250, 1300])
    static let bm1370 = AsicTuning(defaultFrequencyMHz: 525, defaultVoltageMV: 1150,
                                   frequencyOptions: [400, 490, 525, 550, 600, 625, 690],
                                   voltageOptions: [1000, 1060, 1100, 1150, 1200, 1250])
    /// Gamma Duo runs the BM1370 at lower clocks.
    static let bm1370XP = AsicTuning(defaultFrequencyMHz: 400, defaultVoltageMV: 1150,
                                     frequencyOptions: [350, 375, 380, 400, 410],
                                     voltageOptions: [1000, 1060, 1100, 1150, 1200, 1250])
    /// Gamma Hex ships at the top BM1370 clock.
    static let bm1370Hex = AsicTuning(defaultFrequencyMHz: 690, defaultVoltageMV: 1200,
                                      frequencyOptions: [400, 490, 525, 550, 600, 625, 690],
                                      voltageOptions: [1000, 1060, 1100, 1150, 1200, 1250])
    static let bm1373 = AsicTuning(defaultFrequencyMHz: 327, defaultVoltageMV: 1000,
                                   frequencyOptions: [327, 350, 375, 380, 400, 410],
                                   voltageOptions: [1000, 1060, 1100, 1150, 1200, 1250])

    /// Tuning for an `ASICModel` string (`"BM1370"`, `"BM1372/BM1373"`, …).
    static func forAsic(_ model: String) -> AsicTuning? {
        let upper = model.uppercased()
        if upper.contains("1373") || upper.contains("1372") { return .bm1373 }
        if upper.contains("1370") { return .bm1370 }
        if upper.contains("1368") { return .bm1368 }
        if upper.contains("1366") { return .bm1366 }
        if upper.contains("1397") { return .bm1397 }
        return nil
    }

    /// Eco, standard and boost: the firmware steps next to the standard clock and voltage.
    /// `standard` overrides the factory default (NerdOS reports its own).
    func presets(standardFrequencyMHz: Int? = nil, standardVoltageMV: Int? = nil) -> [(name: String, frequencyMHz: Int, voltageMV: Int)] {
        let frequency = standardFrequencyMHz ?? defaultFrequencyMHz
        let voltage = standardVoltageMV ?? defaultVoltageMV
        var result: [(name: String, frequencyMHz: Int, voltageMV: Int)] = []
        if let ecoFrequency = frequencyOptions.last(where: { Double($0) <= Double(frequency) * 0.95 }),
           let ecoVoltage = voltageOptions.last(where: { $0 < voltage }) {
            result.append(("Eco", ecoFrequency, ecoVoltage))
        }
        result.append(("Standard", frequency, voltage))
        if let boostFrequency = frequencyOptions.first(where: { Double($0) >= Double(frequency) * 1.04 }),
           let boostVoltage = voltageOptions.first(where: { $0 > voltage }) {
            result.append(("Boost", boostFrequency, boostVoltage))
        }
        return result
    }
}

extension MinerSystemInfo {
    var firmware: MinerFirmware {
        if let boardVersion, !boardVersion.isEmpty { return .axeOS }
        if deviceModel?.isEmpty == false || stratumDetail != nil { return .nerdOS }
        return .axeOS
    }

    var bitaxeFamily: BitaxeFamily? {
        guard firmware == .axeOS, let boardVersion else { return nil }
        return BitaxeFamily.forBoard(boardVersion)
    }

    /// `"Bitaxe Gamma 601"`, `"Bitaxe Hex 302"`, `"NerdQAxe++"`, `"NerdOCTAXE-γ"` …
    var detectedHardwareTitle: String {
        if firmware == .nerdOS {
            if let model = deviceModel?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
                let known = NerdOSModel.forDeviceModel(model)?.name ?? ""
                return known.isEmpty ? model : known
            }
            return "NerdOS (\(asicCount)x \(asicModel))"
        }
        let board = boardVersion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let family = bitaxeFamily {
            return board.isEmpty ? family.name : "\(family.name) \(board)"
        }
        // Very old AxeOS reported the family in `deviceModel` instead of a known board version.
        if let model = deviceModel?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
            return "Bitaxe \(model.prefix(1).uppercased() + model.dropFirst())"
        }
        return board.isEmpty ? "Bitaxe (\(asicModel))" : "Bitaxe (\(asicModel) v\(board))"
    }

    /// Clock steps of this miner; `nil` for unknown ASICs.
    var asicTuning: AsicTuning? {
        bitaxeFamily?.tuning ?? AsicTuning.forAsic(asicModel)
    }

    /// Expected hashrate in GH/s at a clock: frequency × small cores × chips (as ESP-Miner computes it).
    func expectedHashrateGHs(frequencyMHz: Int) -> Double? {
        guard let smallCoreCount, smallCoreCount > 0 else { return nil }
        return Double(frequencyMHz) * Double(smallCoreCount) * Double(asicCount) / 1000.0
    }
}
