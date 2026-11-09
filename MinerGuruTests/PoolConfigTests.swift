import Foundation
import Testing
@testable import MinerGuru

@Suite("AxeOS pool slots")
struct AxeOSPoolSlotTests {
    @Test func decodesSlotsAndSkipsMalformedEntries() throws {
        let info = try Fixtures.axeSlotsInfo()
        #expect(info.axePools?.map(\.id) == [0, 1, 4])
        #expect(info.primaryPoolIndex == 0)
        #expect(info.secondaryPoolIndex == 1)
        #expect(info.axePools?[2].stratumTLS == 1)
        #expect(info.axePools?[0].stratumSuggestedDifficulty == 1000)
    }

    @Test func olderFirmwareHasNoSlots() throws {
        #expect(try Fixtures.bitaxeInfo().axePools == nil)
        let form = MinerSettingsForm(miner: Fixtures.device(info: try Fixtures.bitaxeInfo()))
        #expect(form.poolAPI == .legacy)
        #expect(form.slots.count == 2)
    }

    @Test func formLoadsEightSlots() throws {
        let form = MinerSettingsForm(miner: Fixtures.device(info: try Fixtures.axeSlotsInfo()))
        #expect(form.poolAPI == .slots)
        #expect(form.slots.count == AxeOSPool.slotCount)
        #expect(form.primary.host == "eusolo.ckpool.org")
        #expect(form.fallback.host == "public-pool.io")
        #expect(form.slots[4].host == "mine.ocean.xyz")
        #expect(form.storedSlots == [0, 1, 4])
        #expect(form.visibleSlots == [0, 1, 2, 4]) // filled slots plus the first free one
    }

    @Test func slotPayloadKeepsAdvancedSettingsAndMaskedPassword() throws {
        var form = MinerSettingsForm(miner: Fixtures.device(info: try Fixtures.axeSlotsInfo()))
        form.slots[4].user = "bc1qocean.rig2"
        let payload = form.poolPayload(supportsDualPool: false)

        #expect(payload.stratumURL == nil) // ignored by AxeOS 2.15+, so not sent
        #expect(payload.primaryPoolIndex == 0)
        #expect(payload.secondaryPoolIndex == 1)
        #expect(payload.pools?.map(\.id) == [0, 1, 4])
        let ocean = try #require(payload.pools?.last)
        #expect(ocean.stratumUser == "bc1qocean.rig2")
        #expect(ocean.stratumTLS == 1)
        #expect(ocean.stratumProtocol == "SV2")
        #expect(ocean.stratumPassword == AxeOSPool.maskedPassword) // firmware keeps the stored password

        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any]
        #expect(json?.keys.sorted() == ["pools", "primaryPoolIndex", "secondaryPoolIndex"])
    }

    @Test func clearedReserveSlotIsDeletedButNotPrimary() throws {
        var form = MinerSettingsForm(miner: Fixtures.device(info: try Fixtures.axeSlotsInfo()))
        form.clearSlot(4)
        #expect(form.slotsToClear == [4])
        #expect(form.poolPayload(supportsDualPool: false).pools?.map(\.id) == [0, 1])

        form.clearSlot(1) // fallback slot: AxeOS refuses to delete it
        #expect(form.slotsToClear == [4])
        #expect(form.poolValidationMessage != nil)
    }

    @Test func incompleteSlotBlocksSaving() throws {
        var form = MinerSettingsForm(miner: Fixtures.device(info: try Fixtures.axeSlotsInfo()))
        #expect(form.poolValidationMessage == nil)
        form.slots[2].host = "solo.atlaspool.io"
        #expect(form.poolValidationMessage?.contains("Slot 3") == true)
    }

    @Test func slotFirmwareHasNoDualPool() throws {
        #expect(!Fixtures.device(info: try Fixtures.axeSlotsInfo()).supportsDualPool)
    }
}

@Suite("Pool quick switch")
struct PoolQuickSwitchTests {
    private let ocean = PoolConfig(name: "OCEAN", host: "mine.ocean.xyz", port: 3334, user: "bc1qocean.rig")
    private let atlas = PoolConfig(name: "Atlas", host: "solo.atlaspool.io", port: 3333, user: "bc1qatlas.rig")

    @Test func selectsExistingSlotAsPrimary() throws {
        var form = MinerSettingsForm(miner: Fixtures.device(info: try Fixtures.axeSlotsInfo()))
        form.makePrimary(ocean)
        #expect(form.primarySlot == 4)
        #expect(form.slots[4].advanced?.stratumTLS == 1) // untouched slot keeps its settings
        #expect(form.slots[0].host == "eusolo.ckpool.org") // previous primary stays stored
    }

    @Test func newPoolGoesIntoFreeSlot() throws {
        var form = MinerSettingsForm(miner: Fixtures.device(info: try Fixtures.axeSlotsInfo()))
        form.makePrimary(atlas)
        #expect(form.primarySlot == 2)
        #expect(form.slots[2].host == "solo.atlaspool.io")
        #expect(form.slots[2].advanced == nil)
        #expect(form.slots[0].host == "eusolo.ckpool.org")
    }

    @Test func makingFallbackPrimarySwapsRoles() throws {
        var form = MinerSettingsForm(miner: Fixtures.device(info: try Fixtures.axeSlotsInfo()))
        form.makePrimary(PoolConfig(name: "Public", host: "public-pool.io", port: 21496, user: "bc1qexamplewallet.bitaxe"))
        #expect(form.primarySlot == 1)
        #expect(form.secondarySlot == 0)
    }

    @Test func legacyFirmwareOverwritesSlots() throws {
        var form = MinerSettingsForm(miner: Fixtures.device(info: try Fixtures.dualPoolInfo()))
        form.makePrimary(ocean)
        form.makeFallback(atlas)
        let payload = form.poolPayload(supportsDualPool: true)
        #expect(payload.stratumURL == "mine.ocean.xyz")
        #expect(payload.stratumPort == 3334)
        #expect(payload.fallbackStratumURL == "solo.atlaspool.io")
        #expect(payload.poolMode == 1) // dual mode and split stay as configured
        #expect(payload.poolBalance == 1)
        #expect(payload.pools == nil)
    }
}

@Suite("Pool library")
@MainActor
struct PoolLibraryTests {
    @Test func importsAllSlotsOnceAndPersists() throws {
        let defaults = Fixtures.defaults()
        let library = PoolLibraryStore(defaults: defaults)
        let miners = [
            Fixtures.device(info: try Fixtures.axeSlotsInfo()),
            Fixtures.device(ip: "192.168.1.29", info: try Fixtures.bitaxeInfo()),
        ]
        #expect(library.importPools(from: miners) == 3)
        #expect(library.importPools(from: miners) == 0)
        #expect(library.pools.allSatisfy { $0.password == "x" }) // masked password is not stored
        #expect(library.pools.first?.name == "CKPool EU (Solo) · bitaxe")

        let reloaded = PoolLibraryStore(defaults: defaults)
        #expect(reloaded.pools == library.pools)
    }

    @Test func editDuplicateAndRemove() {
        let library = PoolLibraryStore(defaults: Fixtures.defaults())
        var pool = library.add(PoolConfig(name: "OCEAN", host: "stratum+tcp://mine.ocean.xyz:3334", port: 3334, user: "bc1q.rig"))
        #expect(pool.host == "mine.ocean.xyz")

        pool.user = "bc1q.rig2"
        library.update(pool)
        #expect(library.config(id: pool.id)?.user == "bc1q.rig2")

        let copy = try? #require(library.duplicate(id: pool.id))
        #expect(copy?.name == "OCEAN Kopie")
        #expect(library.pools.count == 2)

        library.remove(id: pool.id)
        #expect(library.pools.map(\.id) == [copy?.id])
    }
}

@Suite("Legacy pool passwords")
struct LegacyPoolPasswordTests {
    @Test func unknownPasswordIsNotSent() throws {
        var form = MinerSettingsForm(miner: Fixtures.device(info: try Fixtures.dualPoolInfo()))
        #expect(form.poolPayload(supportsDualPool: true).stratumPassword == nil)
        #expect(form.poolPayload(supportsDualPool: true).fallbackStratumPassword == nil)

        form.assign(PoolConfig(name: "OCEAN", host: "mine.ocean.xyz", port: 3334, user: "bc1q.rig", password: "secret"), toSlot: 0)
        #expect(form.poolPayload(supportsDualPool: true).stratumPassword == "secret")
    }
}
