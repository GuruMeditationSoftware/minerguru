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

            Text("Zuordnung zu Minern")
                .font(.title3.weight(.medium))
                .padding(.top, 4)

            if configurableMiners.isEmpty {
                ContentUnavailableView(
                    "Keine Miner online",
                    systemImage: "cpu",
                    description: Text("Sobald ein Miner Telemetrie liefert, kannst du hier seine Pool-Slots belegen.")
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
        .navigationTitle("Pool-Konfiguration")
        .navigationSubtitle("Pools speichern und Minern zuordnen")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    importFromMiners()
                } label: {
                    Label("Aus Minern auslesen", systemImage: "square.and.arrow.down.on.square")
                }
                .help("Alle auf den Minern konfigurierten Pools in die Bibliothek übernehmen")

                Button {
                    editing = EditingPool(config: PoolConfig(name: "", host: ""), isNew: true)
                } label: {
                    Label("Neuer Pool", systemImage: "plus")
                }
                .help("Neue Pool-Konfiguration anlegen")

                Button {
                    apply(minerIDs: dirtyMinerIDs)
                } label: {
                    Label("Alle übernehmen (\(dirtyMinerIDs.count))", systemImage: "checkmark.circle.fill")
                }
                .help("Alle geänderten Pool-Zuordnungen senden; die Miner starten danach neu")
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
            "Pool-Konfiguration löschen?",
            isPresented: Binding { pendingDelete != nil } set: { if !$0 { pendingDelete = nil } },
            presenting: pendingDelete
        ) { pool in
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) { library.remove(id: pool.id) }
        } message: { pool in
            Text("„\(pool.name)“ wird nur aus der Bibliothek entfernt. Die Miner behalten ihre aktuelle Konfiguration.")
        }
    }

    // MARK: - Library

    private var libraryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Pool-Bibliothek", systemImage: "server.rack")
                    .font(.system(size: 15, weight: .medium))
                Text("\(library.pools.count)")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if library.pools.isEmpty {
                Text("Noch keine Pools gespeichert. Lies die Pools deiner Miner aus oder lege einen neuen an.")
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
                Text(usage == 1 ? "1 Miner" : "\(usage) Miner")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }

            Menu {
                Button("Als Primär-Pool auf allen Minern") { assignEverywhere(pool, asPrimary: true) }
                Button("Als Fallback / Pool 2 auf allen Minern") { assignEverywhere(pool, asPrimary: false) }
            } label: {
                Label("Zuweisen", systemImage: "arrow.right.circle")
            }
            .fixedSize()
            .disabled(configurableMiners.isEmpty)
            .help("Pool in die Entwürfe aller Miner übernehmen – gesendet wird erst mit „Übernehmen & neu starten“")

            Button {
                editing = EditingPool(config: pool, isNew: false)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Bearbeiten")

            Button {
                if let copy = library.duplicate(id: pool.id) {
                    editing = EditingPool(config: copy, isNew: false)
                }
            } label: {
                Image(systemName: "plus.square.on.square")
            }
            .buttonStyle(.borderless)
            .help("Duplizieren (z. B. für einen anderen Worker)")

            Button {
                pendingDelete = pool
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Aus der Bibliothek löschen")
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
            added == 0 ? String(localized: "Keine neuen Pools gefunden.") : String(localized: "\(added) Pool(s) in die Bibliothek übernommen."),
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
