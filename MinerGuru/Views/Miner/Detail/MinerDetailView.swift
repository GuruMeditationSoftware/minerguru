import SwiftUI
import AppKit

/// Detail page of one miner: header, KPIs, pool, charts, live log and hardware info.
struct MinerDetailView: View {
    @ObservedObject var store: MinerStore
    @Environment(\.redactor) private var redactor
    let minerID: UUID

    /// Non-nil while the control dialog is open; the value is the tab it opens on.
    @State private var controlDialogTab: ControlTab?
    @State private var showRawJSONSheet = false
    @StateObject private var logController = MinerLogStreamController()
    @StateObject private var shareTracker = ShareDifficultyTracker()
    @State private var showRestartConfirm = false

    private var miner: MinerDevice? {
        store.miners.first(where: { $0.id == minerID })
    }

    var body: some View {
        if let miner {
            content(for: miner)
        } else {
            ContentUnavailableView(
                "Miner nicht gefunden",
                systemImage: "cpu",
                description: Text("Bitte wähle einen Miner in der Seitenleiste aus.")
            )
        }
    }

    private func content(for miner: MinerDevice) -> some View {
        PageScrollView(spacing: 16) {
            MinerDetailHeader(
                miner: miner,
                tempWarningThresholdC: store.tempWarningThresholdC,
                onShowJSON: { showRawJSONSheet = true },
                onRestart: { showRestartConfirm = true },
                onOpenControl: { openControl(.performance) },
                onRefresh: { refresh(miner) }
            )

            if let info = miner.latestInfo {
                MinerKPIGrid(miner: miner, info: info, tempWarningThresholdC: store.tempWarningThresholdC)
                PoolInformationCard(
                    miner: miner,
                    onConfigurePool: { openControl(.pool) },
                    onRefreshLatency: { refresh(miner) }
                )
                if !PayoutCheck.slots(of: info, expected: [:]).isEmpty {
                    PayoutCheckCard(store: store, alerts: store.alerts, miner: miner, info: info)
                }
                if let block = BlockTemplateSummary(info: info) {
                    BlockTemplateCard(
                        block: block,
                        onOpenWebInterface: miner.webInterfaceURL.map { url in { NSWorkspace.shared.open(url) } }
                    )
                } else {
                    ProbedBlockSection(
                        probes: store.blockProbes,
                        targets: BlockProbeTarget.targets(for: info),
                        isEnabled: store.stratumProbeEnabled
                    )
                }
                MinerTelemetryCharts(
                    miner: miner,
                    info: info,
                    tempWarningThresholdC: store.tempWarningThresholdC,
                    pollingIntervalSeconds: store.pollingIntervalSeconds
                )
                LongTermHistoryCard(history: store.history, miner: miner)
                ShareDifficultyChartCard(tracker: shareTracker, isLiveLogRunning: logController.isRunning)
                MinerLiveLogSectionView(miner: miner, logController: logController)
                MinerHardwareSection(miner: miner, info: info)
            } else {
                MinerOfflinePlaceholder(miner: miner) { refresh(miner) }
            }
        }
        .onAppear { startShareTracking(host: miner.ipAddress) }
        .onDisappear { shareTracker.stopSampling() }
        .navigationTitle(miner.displayName)
        .navigationSubtitle("\(miner.hardwareTitle) • \(redactor.ip(miner.ipAddress))")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                MinerAlertMuteButton(alerts: store.alerts, minerID: miner.id)

                Button { refresh(miner) } label: {
                    Label("Aktualisieren", systemImage: "arrow.clockwise")
                }
                .help("Telemetrie & Pool-Latenz jetzt aktualisieren")

                Button {
                    if let url = miner.webInterfaceURL { NSWorkspace.shared.open(url) }
                } label: {
                    Label("Weboberfläche", systemImage: "safari")
                }
                .help("Miner-Weboberfläche im Browser öffnen")

                Button { openControl(.performance) } label: {
                    Label("Einstellungen & Steuerung", systemImage: "slider.horizontal.3")
                }
                .help("Takt, Lüfter, Pool und System konfigurieren")
            }
        }
        .sheet(item: $controlDialogTab) { tab in
            MinerControlView(store: store, minerID: miner.id, initialTab: tab)
        }
        .sheet(isPresented: $showRawJSONSheet) {
            RawJSONInspectorSheet(miner: miner)
        }
        .alert("Miner neu starten?", isPresented: $showRestartConfirm) {
            Button("Abbrechen", role: .cancel) {}
            Button("Neu starten", role: .destructive) {
                Task { await store.restartMiner(minerID: miner.id) }
            }
        } message: {
            Text("Soll \(redactor.freeText(miner.displayName)) (\(redactor.ip(miner.ipAddress))) jetzt neu gestartet werden?")
        }
    }

    private func openControl(_ tab: ControlTab) {
        controlDialogTab = tab
    }

    /// Live-log lines feed the share chart directly; without a running log the tracker samples once a minute.
    private func startShareTracking(host: String) {
        let tracker = shareTracker
        let log = logController
        log.onEntries = { [weak tracker] entries in tracker?.ingest(entries) }
        tracker.startSampling(host: host) { [weak log] in log?.isRunning ?? false }
    }

    private func refresh(_ miner: MinerDevice) {
        Task { await store.refreshMiner(id: miner.id) }
    }
}

/// Shown when the miner has never answered (no telemetry yet).
private struct MinerOfflinePlaceholder: View {
    let miner: MinerDevice
    @Environment(\.redactor) private var redactor
    let onReconnect: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            DeviceCardView(spec: DeviceCardSpec(miner: miner), width: 168, led: .init(state: miner.connectionState))
                .padding(.bottom, 8)
            Text("\(redactor.freeText(miner.displayName)) (\(redactor.ip(miner.ipAddress))) antwortet derzeit nicht")
                .font(.system(size: 15, weight: .medium))
            if case .offline(let reason) = miner.connectionState {
                Text(reason)
                    .font(.mono(11))
                    .foregroundStyle(.tertiary)
            }
            Button(action: onReconnect) {
                Label("Erneut verbinden", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .nativeCard()
    }
}

/// Bell in the toolbar: mutes alerts for this miner only.
private struct MinerAlertMuteButton: View {
    @ObservedObject var alerts: AlertCenter
    let minerID: UUID

    var body: some View {
        if alerts.isEnabled {
            let muted = alerts.isMuted(minerID)
            Button {
                alerts.setMuted(!muted, minerID: minerID)
            } label: {
                Label(muted ? "Benachrichtigungen an" : "Stummschalten", systemImage: muted ? "bell.slash" : "bell")
            }
            .help(muted ? "Benachrichtigungen für diesen Miner wieder einschalten" : "Benachrichtigungen für diesen Miner stummschalten")
        }
    }
}
