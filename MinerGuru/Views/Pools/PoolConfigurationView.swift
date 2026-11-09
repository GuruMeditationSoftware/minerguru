import SwiftUI

/// Pool configuration page: library of saved pools and their assignment to the pool slots of every miner.
struct PoolConfigurationView: View {
    @ObservedObject var store: MinerStore
    @ObservedObject private var library: PoolLibraryStore
    @Environment(\.redactor) private var redactor

    /// Unsaved pool settings per miner, and the state they were loaded from.
    @State private var drafts: [UUID: MinerSettingsForm] = [:]
    @State private var baselines: [UUID: MinerSettingsForm] = [:]
    @State private var applying: Set<UUID> = []
    @State private var errors: [UUID: String] = [:]
    @State private var editing: EditingPool?
    @State private var pendingDelete: PoolConfig?

    private struct EditingPool: Identifiable {
        var config: PoolConfig
        let isNew: Bool
        var id: UUID { config.id }
    }

    init(store: MinerStore) {
        self.store = store
        self._library = ObservedObject(wrappedValue: store.poolLibrary)
    }

    private var configurableMiners: [MinerDevice] {
        store.miners.filter { drafts[$0.id] != nil }
    }

    private var dirtyMinerIDs: [UUID] {
        configurableMiners.map(\.id).filter(isDirty)
    }

    var body: some View {
        PageScrollView {
            libraryCard
            PoolSchedulesCard(store: store)

            Text("Assignment to Miners")
                .font(.title3.weight(.medium))
                .padding(.top, 4)

            if configurableMiners.isEmpty {
                ContentUnavailableView(
                    "No Miners Online",
                    systemImage: "cpu",
                    description: Text("As soon as a miner reports telemetry, you can fill its pool slots here.")
                )
                .frame(maxWidth: .infinity)
            } else {
                AdaptiveGrid(minColumnWidth: 440) {
                    ForEach(configurableMiners) { miner in
                        MinerPoolAssignmentCard(
                            miner: miner,
                            library: library,
                            form: draftBinding(miner.id),
                            isDirty: isDirty(miner.id),
                            isApplying: applying.contains(miner.id),
                            errorMessage: errors[miner.id],
                            onApply: { apply(minerIDs: [miner.id]) },
                            onReset: { reload(miner.id, force: true) },
                            onSaveToLibrary: saveToLibrary
                        )
                    }
                }
            }
        }
        .navigationTitle("Pool Configuration")
        .navigationSubtitle("Save pools and assign them to miners")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    importFromMiners()
                } label: {
                    Label("Read from Miners", systemImage: "square.and.arrow.down.on.square")
                }
                .help("Add all pools configured on the miners to the library")

                Button {
                    editing = EditingPool(config: PoolConfig(name: "", host: ""), isNew: true)
                } label: {
                    Label("New Pool", systemImage: "plus")
                }
                .help("Create a new pool configuration")

                Button {
                    apply(minerIDs: dirtyMinerIDs)
                } label: {
                    Label("Apply All (\(dirtyMinerIDs.count))", systemImage: "checkmark.circle.fill")
                }
                .help("Send all changed pool assignments; the miners restart afterwards")
                .disabled(dirtyMinerIDs.isEmpty || dirtyMinerIDs.contains { drafts[$0]?.poolValidationMessage != nil })
            }
        }
        .onAppear {
            // First visit: fill the library with the pools that are already on the miners.
            if library.pools.isEmpty { library.importPools(from: store.miners) }
            syncDrafts()
        }
        .onChange(of: store.miners) { _, _ in syncDrafts() }
        .sheet(item: $editing) { item in
            PoolConfigEditorSheet(config: item.config, isNew: item.isNew) { saved in
                if item.isNew { library.add(saved) } else { library.update(saved) }
            }
        }
        .alert(
            "Delete Pool Configuration?",
            isPresented: Binding { pendingDelete != nil } set: { if !$0 { pendingDelete = nil } },
            presenting: pendingDelete
        ) { pool in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { library.remove(id: pool.id) }
        } message: { pool in
            Text("“\(pool.name)” is only removed from the library. The miners keep their current configuration.")
        }
    }

    // MARK: - Library

    private var libraryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Pool Library", systemImage: "server.rack")
                    .font(.system(size: 15, weight: .medium))
                Text("\(library.pools.count)")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if library.pools.isEmpty {
                Text("No pools saved yet. Read the pools from your miners or create a new one.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(library.pools) { pool in
                        libraryRow(pool)
                        if pool.id != library.pools.last?.id { Divider() }
                    }
                }
            }
        }
        .padding(16)
        .nativeCard()
    }

    private func libraryRow(_ pool: PoolConfig) -> some View {
        HStack(spacing: 10) {
            CoinBadgeView(coin: MinedCoin.detect(poolHost: pool.host, stratumUser: pool.user), compact: true)
                .frame(width: 56, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(pool.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(pool.user.isEmpty ? pool.hostAndPort : "\(pool.hostAndPort) • \(redactor.stratumUser(pool.user))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            let usage = usageCount(pool)
            if usage > 0 {
                Text(usage == 1 ? "1 miner" : "\(usage) miners")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }

            Menu {
                Button("As Primary Pool on All Miners") { assignEverywhere(pool, asPrimary: true) }
                Button("As Fallback / Pool 2 on All Miners") { assignEverywhere(pool, asPrimary: false) }
            } label: {
                Label("Assign", systemImage: "arrow.right.circle")
            }
            .fixedSize()
            .disabled(configurableMiners.isEmpty)
            .help("Put the pool into the drafts of all miners – nothing is sent until “Apply & Restart”")

            Button {
                editing = EditingPool(config: pool, isNew: false)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit")

            Button {
                if let copy = library.duplicate(id: pool.id) {
                    editing = EditingPool(config: copy, isNew: false)
                }
            } label: {
                Image(systemName: "plus.square.on.square")
            }
            .buttonStyle(.borderless)
            .help("Duplicate (e.g. for another worker)")

            Button {
                pendingDelete = pool
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete from library")
        }
        .controlSize(.small)
        .padding(.vertical, 6)
    }

    private func usageCount(_ pool: PoolConfig) -> Int {
        configurableMiners.filter { miner in
            baselines[miner.id]?.slots.contains { pool.matches($0) } ?? false
        }.count
    }

    // MARK: - Drafts

    private func draftBinding(_ id: UUID) -> Binding<MinerSettingsForm> {
        Binding {
            drafts[id] ?? MinerSettingsForm()
        } set: {
            drafts[id] = $0
            errors[id] = nil
        }
    }

    private func isDirty(_ id: UUID) -> Bool {
        guard let draft = drafts[id], let baseline = baselines[id] else { return false }
        return !draft.hasSamePoolSettings(as: baseline)
    }

    /// Picks up new telemetry for miners without unsaved changes; drops removed miners.
    private func syncDrafts() {
        let ids = Set(store.miners.map(\.id))
        drafts = drafts.filter { ids.contains($0.key) }
        baselines = baselines.filter { ids.contains($0.key) }
        for miner in store.miners { reload(miner.id, force: false) }
    }

    private func reload(_ id: UUID, force: Bool) {
        guard let miner = store.miners.first(where: { $0.id == id }), miner.latestInfo != nil else { return }
        guard force || (!isDirty(id) && !applying.contains(id)) else { return }
        let fresh = MinerSettingsForm(miner: miner)
        if let baseline = baselines[id], baseline.hasSamePoolSettings(as: fresh), !force { return }
        baselines[id] = fresh
        drafts[id] = fresh
        errors[id] = nil
    }

    private func assignEverywhere(_ pool: PoolConfig, asPrimary: Bool) {
        for miner in configurableMiners {
            guard var draft = drafts[miner.id] else { continue }
            if asPrimary { draft.makePrimary(pool) } else { draft.makeFallback(pool) }
            drafts[miner.id] = draft
            errors[miner.id] = nil
        }
    }

    private func apply(minerIDs: [UUID]) {
        for id in minerIDs {
            guard let draft = drafts[id], draft.poolValidationMessage == nil else { continue }
            applying.insert(id)
            errors[id] = nil
            Task {
                do {
                    try await store.applyPoolSettings(draft, minerID: id)
                    applying.remove(id)
                    reload(id, force: true)
                } catch is CancellationError {
                    applying.remove(id)
                } catch {
                    applying.remove(id)
                    errors[id] = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Library actions

    private func importFromMiners() {
        let added = library.importPools(from: store.miners)
        store.showBanner(
            added == 0 ? String(localized: "No new pools found.") : String(localized: "Added \(added) pool(s) to the library."),
            isError: false
        )
    }

    private func saveToLibrary(_ endpoint: MinerSettingsForm.PoolEndpoint) {
        let config = PoolConfig(
            name: PoolConfig.suggestedName(host: endpoint.host, port: endpoint.port, user: endpoint.user),
            endpoint: endpoint
        )
        editing = EditingPool(config: config, isNew: true)
    }
}
