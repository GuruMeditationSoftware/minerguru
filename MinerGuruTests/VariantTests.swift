import Foundation
import Testing
@testable import MinerGuru

/// Every Bitaxe and NerdOS variant, from `MockMiners/variants` (generated from the firmware sources,
/// see `MockMiners/make_variants.py`).
struct MinerVariant: CustomTestStringConvertible, Sendable {
    let file: String
    let title: String
    let firmware: MinerFirmware
    let chips: Int
    let poolAPI: MinerSettingsForm.PoolAPI
    let dualPool: Bool
    /// Frequency / voltage of the "Standard" profile.
    let standard: (Int, Int)
    let presets: [String]

    var testDescription: String { file }

    func load() throws -> MinerSystemInfo {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MockMiners/variants/\(file).json")
        return try JSONDecoder().decode(MinerSystemInfo.self, from: Data(contentsOf: url))
    }

    static let all: [MinerVariant] = [
        // AxeOS: model from the board table, chip count from asicCount / hashrateMonitor / board table
        .init(file: "bitaxe-max-102_axeos-2.5.0", title: "Bitaxe Max 102", firmware: .axeOS, chips: 1,
              poolAPI: .legacy, dualPool: false, standard: (425, 1400), presets: ["Eco", "Standard", "Boost"]),
        .init(file: "bitaxe-ultra-204_axeos-2.8.0", title: "Bitaxe Ultra 204", firmware: .axeOS, chips: 1,
              poolAPI: .legacy, dualPool: false, standard: (485, 1200), presets: ["Eco", "Standard", "Boost"]),
        .init(file: "bitaxe-supra-401_axeos-2.10.0", title: "Bitaxe Supra 401", firmware: .axeOS, chips: 1,
              poolAPI: .legacy, dualPool: false, standard: (490, 1166), presets: ["Eco", "Standard", "Boost"]),
        .init(file: "bitaxe-hex-302_axeos-2.11.0", title: "Bitaxe Hex 302", firmware: .axeOS, chips: 6,
              poolAPI: .legacy, dualPool: false, standard: (485, 1200), presets: ["Eco", "Standard", "Boost"]),
        .init(file: "bitaxe-gamma-601_axeos-2.13.2", title: "Bitaxe Gamma 601", firmware: .axeOS, chips: 1,
              poolAPI: .legacy, dualPool: false, standard: (525, 1150), presets: ["Eco", "Standard", "Boost"]),
        .init(file: "bitaxe-supra-hex-701_axeos-2.14.2", title: "Bitaxe Supra Hex 701", firmware: .axeOS, chips: 6,
              poolAPI: .legacy, dualPool: false, standard: (490, 1166), presets: ["Eco", "Standard", "Boost"]),
        .init(file: "bitaxe-gamma-601_axeos-2.15.3", title: "Bitaxe Gamma 601", firmware: .axeOS, chips: 1,
              poolAPI: .slots, dualPool: false, standard: (525, 1150), presets: ["Eco", "Standard", "Boost"]),
        .init(file: "bitaxe-gamma-duo-650_axeos-2.15.4", title: "Bitaxe Gamma Duo 650", firmware: .axeOS, chips: 2,
              poolAPI: .slots, dualPool: false, standard: (400, 1150), presets: ["Eco", "Standard"]),
        .init(file: "bitaxe-gt-801_axeos-2.15.4", title: "Bitaxe GT 801", firmware: .axeOS, chips: 2,
              poolAPI: .slots, dualPool: false, standard: (525, 1150), presets: ["Eco", "Standard", "Boost"]),
        .init(file: "bitaxe-naja-duo-1201_axeos-2.15.4", title: "Bitaxe Naja Duo 1201", firmware: .axeOS, chips: 2,
              poolAPI: .slots, dualPool: false, standard: (327, 1000), presets: ["Standard", "Boost"]),
        .init(file: "bitaxe-gamma-hex-1300_axeos-2.15.4", title: "Bitaxe Gamma Hex 1300", firmware: .axeOS, chips: 6,
              poolAPI: .slots, dualPool: false, standard: (690, 1200), presets: ["Eco", "Standard"]),
        // NerdOS: model from deviceModel, standard profile = factory clock reported by the device
        .init(file: "nerdaxe_nerdos-1.1.0", title: "NerdAxe", firmware: .nerdOS, chips: 1,
              poolAPI: .legacy, dualPool: true, standard: (485, 1200), presets: ["Eco", "Standard", "Boost"]),
        .init(file: "nerdaxe-gamma_nerdos-1.1.0", title: "NerdAxeGamma", firmware: .nerdOS, chips: 1,
              poolAPI: .legacy, dualPool: true, standard: (515, 1150), presets: ["Eco", "Standard", "Boost"]),
        .init(file: "nerdaxe-gaia_nerdos-1.1.0", title: "NerdAxeGaia", firmware: .nerdOS, chips: 1,
              poolAPI: .legacy, dualPool: true, standard: (350, 940), presets: ["Standard", "Boost"]),
        .init(file: "nerdqaxe-plus_nerdos-1.1.0", title: "NerdQAxe+", firmware: .nerdOS, chips: 4,
              poolAPI: .legacy, dualPool: true, standard: (490, 1250), presets: ["Eco", "Standard", "Boost"]),
        .init(file: "nerdqaxe-plusplus_nerdos-1.1.0", title: "NerdQAxe++", firmware: .nerdOS, chips: 4,
              poolAPI: .legacy, dualPool: true, standard: (600, 1150), presets: ["Eco", "Standard", "Boost"]),
        .init(file: "nerdqaxe-plusplus_nerdos-legacy", title: "NerdQAxe++", firmware: .nerdOS, chips: 4,
              poolAPI: .legacy, dualPool: false, standard: (600, 1150), presets: ["Eco", "Standard", "Boost"]),
        .init(file: "nerdqx_nerdos-1.1.0", title: "NerdQX", firmware: .nerdOS, chips: 4,
              poolAPI: .legacy, dualPool: true, standard: (777, 1200), presets: ["Eco", "Standard"]),
        .init(file: "nerdhaxe-gamma_nerdos-1.1.0", title: "NerdHaxe-γ", firmware: .nerdOS, chips: 6,
              poolAPI: .legacy, dualPool: true, standard: (600, 1150), presets: ["Eco", "Standard", "Boost"]),
        .init(file: "nerdoctaxe-gamma_nerdos-1.1.0", title: "NerdOCTAXE-γ", firmware: .nerdOS, chips: 8,
              poolAPI: .legacy, dualPool: true, standard: (700, 1210), presets: ["Eco", "Standard"]),
        .init(file: "nerdoctaxe-plus_nerdos-1.1.0", title: "NerdOCTAXE+", firmware: .nerdOS, chips: 8,
              poolAPI: .legacy, dualPool: true, standard: (490, 1250), presets: ["Eco", "Standard", "Boost"]),
        .init(file: "nerdeko_nerdos-1.1.0", title: "NerdEKO", firmware: .nerdOS, chips: 12,
              poolAPI: .legacy, dualPool: true, standard: (600, 1150), presets: ["Eco", "Standard", "Boost"]),
        .init(file: "q1370_nerdos-1.1.0", title: "Q1370", firmware: .nerdOS, chips: 4,
              poolAPI: .legacy, dualPool: true, standard: (600, 1150), presets: ["Eco", "Standard", "Boost"]),
        // Factory clock 425 MHz is already above the highest BM1373 step (410), so there is no boost.
        .init(file: "q1373_nerdos-1.1.0", title: "Q1373", firmware: .nerdOS, chips: 4,
              poolAPI: .legacy, dualPool: true, standard: (425, 1010), presets: ["Eco", "Standard"]),
    ]
}

@Suite("Miner variants")
struct VariantTests {
    @Test func everyGeneratedVariantIsCovered() throws {
        let folder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MockMiners/variants")
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(5)) }
        #expect(Set(files) == Set(MinerVariant.all.map(\.file)))
    }

    @Test(arguments: MinerVariant.all)
    func identification(variant: MinerVariant) throws {
        let info = try variant.load()
        #expect(info.firmware == variant.firmware)
        #expect(info.detectedHardwareTitle == variant.title)
        #expect(info.asicCount == variant.chips)
    }

    @Test(arguments: MinerVariant.all)
    func poolHandling(variant: MinerVariant) throws {
        let miner = Fixtures.device(info: try variant.load())
        let form = MinerSettingsForm(miner: miner)
        #expect(form.poolAPI == variant.poolAPI)
        #expect(miner.supportsDualPool == variant.dualPool)
        #expect(form.poolValidationMessage == nil)

        let payload = form.poolPayload(supportsDualPool: miner.supportsDualPool)
        if variant.poolAPI == .slots {
            #expect(payload.pools?.isEmpty == false)
            #expect(payload.stratumURL == nil)
        } else {
            #expect(payload.pools == nil)
            #expect(payload.stratumURL?.isEmpty == false)
        }
        // AxeOS has no dual-pool mode: never send its fields there.
        #expect((payload.poolMode != nil) == variant.dualPool)
    }

    @Test(arguments: MinerVariant.all)
    func clockProfiles(variant: MinerVariant) throws {
        let miner = Fixtures.device(info: try variant.load())
        let presets = miner.recommendedPresets
        #expect(presets.map(\.name) == variant.presets)
        let standard = try #require(presets.first { $0.name == "Standard" })
        #expect(standard.frequencyMHz == variant.standard.0)
        #expect(standard.coreVoltageMV == variant.standard.1)
        for preset in presets {
            #expect(miner.frequencyRange.contains(preset.frequencyMHz))
            #expect(miner.coreVoltageRange.contains(preset.coreVoltageMV))
            #expect(preset.subtitle.hasPrefix("≈ "))
        }
        // Eco below, boost above the standard profile
        if let eco = presets.first(where: { $0.name == "Eco" }) {
            #expect(eco.frequencyMHz < standard.frequencyMHz && eco.coreVoltageMV < standard.coreVoltageMV)
        }
        if let boost = presets.first(where: { $0.name == "Boost" }) {
            #expect(boost.frequencyMHz > standard.frequencyMHz && boost.coreVoltageMV > standard.coreVoltageMV)
        }
    }

    @Test(arguments: MinerVariant.all)
    func expectedHashrateMatchesReportedHashrate(variant: MinerVariant) throws {
        let info = try variant.load()
        let expected = try #require(info.expectedHashrateGHs(frequencyMHz: info.frequencyMHz))
        // The generator reports 97 % of the theoretical hashrate, like a healthy miner.
        #expect(abs(info.hashRate / expected - 0.97) < 0.01)
    }
}

@Suite("Hardware tables")
struct HardwareTableTests {
    @Test(arguments: [
        ("2.2", "Bitaxe Max"), ("0.11", "Bitaxe Ultra"), ("207", "Bitaxe Ultra"), ("303", "Bitaxe Hex"),
        ("403", "Bitaxe Supra"), ("603", "Bitaxe Gamma"), ("650", "Bitaxe Gamma Duo"), ("702", "Bitaxe Supra Hex"),
        ("801", "Bitaxe GT"), ("1201", "Bitaxe Naja Duo"), ("1300", "Bitaxe Gamma Hex"),
    ])
    func boardVersions(board: String, family: String) {
        #expect(BitaxeFamily.forBoard(board)?.name == family)
    }

    @Test(arguments: [
        ("NerdQAxePlusPlus", "NerdQAxe++", 4), ("NerdQAxePlus", "NerdQAxe+", 4), ("NerdOCTAXE-γ", "NerdOCTAXE-γ", 8),
        ("NerdAxe", "NerdAxe", 1), ("SomeNewNerd", "SomeNewNerd", 1),
    ])
    func nerdOSModelsWithoutChipCount(deviceModel: String, title: String, chips: Int) throws {
        let info = try Fixtures.info(["deviceModel": deviceModel, "hashRate": 1000, "ASICModel": "BM1370"])
        #expect(info.firmware == .nerdOS)
        #expect(info.detectedHardwareTitle == title)
        #expect(info.asicCount == chips)
    }

    @Test func unknownBoardFallsBackToAsic() throws {
        let info = try Fixtures.bitaxeInfo(overrides: ["boardVersion": "999", "ASICModel": "BM1370"])
        #expect(info.firmware == .axeOS)
        #expect(info.detectedHardwareTitle == "Bitaxe (BM1370 v999)")
        #expect(info.asicTuning == .bm1370)
    }

    @Test func unknownAsicHasNoProfilesButKeepsDefaultRanges() throws {
        let info = try Fixtures.bitaxeInfo(overrides: ["boardVersion": "999", "ASICModel": "BM9999"])
        let miner = Fixtures.device(info: info)
        #expect(miner.recommendedPresets.isEmpty)
        #expect(miner.frequencyRange == MinerSettingsForm.frequencyRange)
    }
}
