import Foundation

/// Editable copy of a miner's settings for the control dialog, and the `PATCH /api/system`
/// payloads built from it. Pure value type so the conversion rules can be unit-tested.
struct MinerSettingsForm: Equatable {
    // Performance & cooling
    var frequencyMHz = 525
    var coreVoltageMV = 1150
    var autoFanSpeed = true
    var manualFanPercent: Double = 75

    // Names
    var customAlias = ""
    var deviceHostname = ""

    // Pools
    var poolAPI = PoolAPI.legacy
    var poolMode = PoolMode.failover
    var poolBalance: Double = 50
    /// Two slots (primary, fallback) on older AxeOS and NerdOS, eight on AxeOS 2.15+.
    var slots = [PoolEndpoint(), PoolEndpoint()]
    var primarySlot = 0
    var secondarySlot = 1
    /// Slots that held a pool on the miner when the form was loaded (AxeOS 2.15+).
    var storedSlots: Set<Int> = []

    enum PoolAPI: Equatable {
        /// `stratumURL` / `fallbackStratumURL` fields (AxeOS before 2.15, NerdOS).
        case legacy
        /// `pools[]` with `primaryPoolIndex` / `secondaryPoolIndex` (AxeOS 2.15+).
        case slots
    }

    enum PoolMode: Int, Equatable {
        case failover = 0
        case dual = 1
    }

    struct PoolEndpoint: Equatable {
        var host = ""
        var port = 3333
        var user = ""
        var password = "x"
        /// Slot as read from AxeOS 2.15+; its advanced fields are written back unchanged.
        var advanced: AxeOSPool?

        var hasContent: Bool { !host.isEmpty || !user.isEmpty }

        /// Host and user set – the minimum AxeOS accepts for a slot.
        var isComplete: Bool {
            !StratumHost.clean(host).isEmpty && !user.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        init(host: String = "", port: Int = 3333, user: String = "", password: String = "x", advanced: AxeOSPool? = nil) {
            self.host = host
            self.port = port
            self.user = user
            self.password = password
            self.advanced = advanced
        }

        init(axePool: AxeOSPool) {
            self.init(
                host: StratumHost.clean(axePool.stratumURL),
                port: axePool.stratumPort,
                user: axePool.stratumUser,
                password: axePool.stratumPassword ?? AxeOSPool.maskedPassword,
                advanced: axePool
            )
        }

        /// Slot payload for AxeOS 2.15+: the edited basics on top of the advanced settings read from the miner.
        func axePool(id: Int) -> AxeOSPool {
            var pool = advanced ?? AxeOSPool(id: id, stratumURL: "", stratumPort: port, stratumUser: "")
            pool.id = id
            pool.stratumURL = StratumHost.clean(host)
            pool.stratumPort = port
            pool.stratumUser = user.trimmingCharacters(in: .whitespacesAndNewlines)
            pool.stratumPassword = password.isEmpty ? "x" : password
            return pool
        }
    }

    static let frequencyRange = 350...800
    static let coreVoltageRange = 1000...1400
    static let manualFanRange: ClosedRange<Double> = 20...100

    init() {}

    /// Pre-fills the form from the miner's current telemetry.
    init(miner: MinerDevice) {
        customAlias = miner.customName ?? ""
        guard let info = miner.latestInfo else { return }
        frequencyMHz = info.frequencyMHz
        coreVoltageMV = info.coreVoltageTargetMV
        autoFanSpeed = info.autoFanSpeed
        manualFanPercent = (info.fanSpeedPercent > 0 ? info.fanSpeedPercent : 75)
            .clamped(to: Self.manualFanRange)
        deviceHostname = info.hostname
        poolMode = info.isDualPoolMining || info.stratumDetail?.poolMode == 1 ? .dual : .failover
        poolBalance = Double(info.dualPoolPrimaryPercent)
        if let axePools = info.axePools {
            poolAPI = .slots
            slots = (0..<AxeOSPool.slotCount).map { index in
                axePools.first { $0.id == index }.map(PoolEndpoint.init(axePool:)) ?? PoolEndpoint()
            }
            let slotRange = 0...(AxeOSPool.slotCount - 1)
            primarySlot = (info.primaryPoolIndex ?? 0).clamped(to: slotRange)
            secondarySlot = (info.secondaryPoolIndex ?? 1).clamped(to: slotRange)
            storedSlots = Set(axePools.map(\.id).filter(slotRange.contains))
        } else {
            // The firmware does not report passwords; an empty one is not sent and stays unchanged on the miner.
            primary = PoolEndpoint(host: StratumHost.clean(info.stratumURL), port: info.stratumPort, user: info.stratumUser, password: "")
            fallback = PoolEndpoint(host: StratumHost.clean(info.fallbackStratumURL), port: info.fallbackStratumPort, user: info.fallbackStratumUser, password: "")
        }
    }

    // MARK: - Derived values

    /// Pool the miner mines on (dual mode: pool 1).
    var primary: PoolEndpoint {
        get { slots[primarySlot] }
        set { slots[primarySlot] = newValue }
    }

    /// Fallback pool (dual mode: pool 2).
    var fallback: PoolEndpoint {
        get { slots[secondarySlot] }
        set { slots[secondarySlot] = newValue }
    }

    /// Puts a library pool into a slot. Advanced AxeOS settings are kept only if the pool host stays the same.
    mutating func assign(_ config: PoolConfig, toSlot index: Int) {
        guard slots.indices.contains(index) else { return }
        var endpoint = config.endpoint
        if StratumHost.clean(slots[index].host).lowercased() == config.host.lowercased() {
            endpoint.advanced = slots[index].advanced
        }
        slots[index] = endpoint
    }

    /// Makes `config` the primary pool. On AxeOS 2.15+ an existing slot with that pool is just selected,
    /// otherwise the pool goes into a free slot so the previous pools stay stored on the miner.
    mutating func makePrimary(_ config: PoolConfig) {
        let target = slotIndex(for: config) ?? freeSlot ?? primarySlot
        if !config.matches(slots[target]) { assign(config, toSlot: target) }
        if target == secondarySlot, poolAPI == .slots { secondarySlot = primarySlot }
        primarySlot = target
    }

    /// Makes `config` the fallback (dual mode: pool 2), analogous to `makePrimary`.
    mutating func makeFallback(_ config: PoolConfig) {
        let target = slotIndex(for: config) ?? freeSlot ?? secondarySlot
        // Swapping roles only works if the current fallback can take over as primary.
        if target == primarySlot, poolAPI == .legacy || !slots[secondarySlot].hasContent { return }
        if !config.matches(slots[target]) { assign(config, toSlot: target) }
        if target == primarySlot { primarySlot = secondarySlot }
        secondarySlot = target
    }

    private func slotIndex(for config: PoolConfig) -> Int? {
        guard poolAPI == .slots else { return nil }
        return slots.firstIndex { config.matches($0) }
    }

    private var freeSlot: Int? {
        guard poolAPI == .slots else { return nil }
        return slots.indices.first { !slots[$0].hasContent && $0 != primarySlot && $0 != secondarySlot }
    }

    /// Slots worth showing: filled ones, primary and fallback, plus one free slot to add a pool.
    var visibleSlots: [Int] {
        guard poolAPI == .slots else { return Array(slots.indices) }
        var visible = slots.indices.filter { slots[$0].hasContent || $0 == primarySlot || $0 == secondarySlot }
        if let free = slots.indices.first(where: { !visible.contains($0) }) {
            visible.append(free)
        }
        return visible.sorted()
    }

    mutating func clearSlot(_ index: Int) {
        guard slots.indices.contains(index) else { return }
        slots[index] = PoolEndpoint()
    }

    /// Slots that were stored on the miner and have been emptied; AxeOS refuses to delete primary / fallback.
    var slotsToClear: [Int] {
        guard poolAPI == .slots else { return [] }
        return storedSlots
            .filter { !slots[$0].hasContent && $0 != primarySlot && $0 != secondarySlot }
            .sorted()
    }

    /// A slot whose address does not fit its pool; sending stays possible.
    var poolCoinWarning: String? {
        for (index, slot) in slots.enumerated() where slot.hasContent {
            if let coins = MinedCoin.mismatch(poolHost: slot.host, stratumUser: slot.user) {
                return String(localized: "\(slotTitle(index)): this address belongs to \(coins.address.symbol), the pool mines \(coins.pool.symbol). Payouts could be lost.")
            }
        }
        return nil
    }

    /// Why the pool settings cannot be sent yet, or `nil`.
    var poolValidationMessage: String? {
        if StratumHost.clean(primary.host).isEmpty {
            return String(localized: "The primary pool needs a host.")
        }
        for (index, slot) in slots.enumerated() where slot.hasContent {
            if !(1...65535).contains(slot.port) {
                return String(localized: "\(slotTitle(index)): Invalid port \(String(slot.port)).")
            }
            if poolAPI == .slots, !slot.isComplete {
                return String(localized: "\(slotTitle(index)): Host and wallet/stratum user are required.")
            }
        }
        if poolAPI == .slots, !slots[secondarySlot].hasContent, secondarySlot != primarySlot,
           storedSlots.contains(secondarySlot) {
            return String(localized: "The fallback slot is empty. Choose another fallback slot or fill this one.")
        }
        return nil
    }

    func slotTitle(_ index: Int) -> String {
        switch poolAPI {
        case .slots: return String(localized: "Slot \(index + 1)")
        case .legacy: return index == 0 ? "Pool 1" : "Pool 2"
        }
    }

    /// Hashrate share of pool 1 / pool 2 in dual-pool mode (1…99 %).
    var primaryPercent: Int { Int(poolBalance).clamped(to: 1...99) }
    var secondaryPercent: Int { 100 - primaryPercent }

    func isCurrent(_ preset: MinerClockPreset) -> Bool {
        frequencyMHz == preset.frequencyMHz && coreVoltageMV == preset.coreVoltageMV
    }

    mutating func apply(_ preset: MinerClockPreset) {
        frequencyMHz = preset.frequencyMHz
        coreVoltageMV = preset.coreVoltageMV
    }

    var trimmedHostname: String {
        deviceHostname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Payloads

    /// Clock, voltage and fan. Keeps the miner's current auto-fan mode (e.g. NerdQAxe PID = 2) when auto stays on.
    func performancePayload(existingAutoFanMode: Int?) -> MinerSystemUpdatePayload {
        MinerSystemUpdatePayload(
            frequency: frequencyMHz,
            coreVoltage: coreVoltageMV,
            overclockEnabled: 1,
            autofanspeed: autoFanSpeed ? max(1, existingAutoFanMode ?? 1) : 0,
            fanspeed: autoFanSpeed ? nil : Int(manualFanPercent)
        )
    }

    /// Pool configuration. Dual-pool fields are only sent to firmware that supports them;
    /// an empty fallback pool is left untouched on the miner. AxeOS 2.15+ gets all filled slots.
    func poolPayload(supportsDualPool: Bool) -> MinerSystemUpdatePayload {
        if poolAPI == .slots {
            let pools = slots.enumerated().compactMap { index, slot in
                slot.isComplete ? slot.axePool(id: index) : nil
            }
            return MinerSystemUpdatePayload(
                pools: pools,
                primaryPoolIndex: primarySlot,
                secondaryPoolIndex: secondarySlot
            )
        }
        let fallbackHost = StratumHost.clean(fallback.host)
        let fallbackUser = fallback.user.trimmingCharacters(in: .whitespacesAndNewlines)
        return MinerSystemUpdatePayload(
            poolMode: supportsDualPool ? poolMode.rawValue : nil,
            poolBalance: supportsDualPool && poolMode == .dual ? primaryPercent : nil,
            stratumURL: StratumHost.clean(primary.host),
            stratumPort: primary.port,
            stratumUser: primary.user.trimmingCharacters(in: .whitespacesAndNewlines),
            stratumPassword: primary.password.isEmpty ? nil : primary.password,
            fallbackStratumURL: fallbackHost.isEmpty ? nil : fallbackHost,
            fallbackStratumPort: fallbackHost.isEmpty ? nil : fallback.port,
            fallbackStratumUser: fallbackUser.isEmpty ? nil : fallbackUser,
            fallbackStratumPassword: fallback.password.isEmpty ? nil : fallback.password
        )
    }

    /// Pool-related part of the form, to tell whether the user changed anything.
    func hasSamePoolSettings(as other: MinerSettingsForm) -> Bool {
        poolAPI == other.poolAPI && poolMode == other.poolMode && primaryPercent == other.primaryPercent
            && slots == other.slots && primarySlot == other.primarySlot && secondarySlot == other.secondarySlot
    }

    var hostnamePayload: MinerSystemUpdatePayload {
        MinerSystemUpdatePayload(hostname: trimmedHostname)
    }
}

extension MinerDevice {
    /// NerdOS reports its dual-pool settings in the `stratum` block; AxeOS has no dual-pool mode.
    var supportsDualPool: Bool {
        latestInfo?.firmware == .nerdOS && latestInfo?.stratumDetail != nil
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
