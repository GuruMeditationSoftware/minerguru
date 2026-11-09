import SwiftUI
import AppKit

struct MainWindowView: View {
    @ObservedObject var store: MinerStore
    @Environment(\.redactor) private var redactor
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    init(store: MinerStore) {
        self.store = store
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 320)
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        PrivacyToggleButton()
                    }
                }
        } detail: {
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Surface.page)
                .overlay(alignment: .bottom) {
                    if let banner = store.statusBannerMessage {
                        HStack(spacing: 8) {
                            Image(systemName: store.statusBannerIsError ? "exclamationmark.triangle" : "checkmark")
                                .foregroundStyle(store.statusBannerIsError ? Signal.warning : Signal.good)
                            Text(banner)
                                .font(.system(size: 13))
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .background(Surface.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.hairline, lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                        .padding(.bottom, 20)
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: PageLayout.windowMinWidth, minHeight: PageLayout.windowMinHeight)
        .sheet(isPresented: $store.showScannerSheet) {
            NetworkScannerSheet(store: store)
        }
        .sheet(isPresented: $store.showAddIPSheet) {
            AddMinerByIPSheet(store: store)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    MinerGuruMark(size: 18)
                    Text("MinerGuru")
                        .font(.system(size: 17, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 16)

                sidebarGroup(nil) {
                    SidebarNavRow(
                        title: "Fleet",
                        systemImage: "square.grid.2x2",
                        trailing: store.onlineMiners.isEmpty ? nil : MinerFormatting.formatHashrate(store.totalHashrateGHs),
                        isSelected: store.selection == .overview || store.selection == nil
                    ) {
                        store.selection = .overview
                    }
                    .keyboardShortcut("1", modifiers: .command)

                    SidebarNavRow(
                        title: "Pools",
                        systemImage: "server.rack",
                        trailing: nil,
                        isSelected: store.selection == .pools
                    ) {
                        store.selection = .pools
                    }
                    .keyboardShortcut("2", modifiers: .command)

                    SidebarNavRow(
                        title: "Power (section)",
                        systemImage: "bolt",
                        trailing: store.onlineMiners.isEmpty ? nil : String(format: "%.0f W", store.totalPowerWatts),
                        isSelected: store.selection == .power
                    ) {
                        store.selection = .power
                    }
                    .keyboardShortcut("3", modifiers: .command)

                    SidebarNavRow(
                        title: "Maintenance",
                        systemImage: "wrench.and.screwdriver",
                        trailing: maintenanceDueCount > 0 ? String(maintenanceDueCount) : nil,
                        isSelected: store.selection == .maintenance
                    ) {
                        store.selection = .maintenance
                    }
                    .keyboardShortcut("4", modifiers: .command)

                    SidebarNavRow(
                        title: "Reports",
                        systemImage: "doc.text",
                        trailing: nil,
                        isSelected: store.selection == .reports
                    ) {
                        store.selection = .reports
                    }
                    .keyboardShortcut("5", modifiers: .command)
                }

                if !store.miners.isEmpty {
                    sidebarGroup("Miners", count: store.miners.count) {
                        ForEach(store.miners) { miner in
                            SidebarMinerRow(
                                miner: miner,
                                tempWarningThresholdC: store.tempWarningThresholdC,
                                isSelected: store.selection == .miner(miner.id)
                            ) {
                                store.selection = .miner(miner.id)
                            }
                            .contextMenu {
                                Button {
                                    if let url = URL(string: "http://\(miner.ipAddress)") {
                                        NSWorkspace.shared.open(url)
                                    }
                                } label: {
                                    Label("Open in Browser", systemImage: "safari")
                                }

                                Button {
                                    Task { await store.refreshMiner(id: miner.id) }
                                } label: {
                                    Label("Refresh Now", systemImage: "arrow.clockwise")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    store.removeMiner(id: miner.id)
                                } label: {
                                    Label("Remove Miner", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
        .background(Surface.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 4) {
                    OpenSettingsButton {
                        Image(systemName: "gearshape")
                            .frame(width: 28, height: 28)
                    }
                    .help("Open Settings")

                    Button {
                        store.showAddIPSheet = true
                    } label: {
                        Label("By IP", systemImage: "plus")
                            .padding(.horizontal, 8)
                            .frame(height: 28)
                    }
                    .help("Add miner by IP address")

                    Button {
                        store.showScannerSheet = true
                    } label: {
                        Label("Scan", systemImage: "dot.radiowaves.left.and.right")
                            .padding(.horizontal, 8)
                            .frame(height: 28)
                    }
                    .help("Search the local network for miners automatically")

                    Spacer()

                    Button {
                        Task { await store.refreshAllMiners() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 28, height: 28)
                    }
                    .disabled(store.isRefreshingAll)
                    .help("Refresh All Miners Now")
                }
                .buttonStyle(.borderless)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(Surface.sidebar)
            }
        }
    }

    /// Group of the sidebar: hairline, mono label with an optional count, rows.
    private func sidebarGroup<Content: View>(_ title: LocalizedStringKey?, count: Int? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Divider()
                .padding(.horizontal, -12)
                .padding(.bottom, title == nil ? 12 : 20)
            if let title {
                HStack {
                    Text(title)
                    Spacer()
                    if let count {
                        Text("\(count)")
                    }
                }
                .sectionLabelStyle()
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            content()
        }
        .padding(.bottom, 20)
    }

    private var maintenanceDueCount: Int { store.maintenance.dueCount() }

    // MARK: - Detail Routing

    @ViewBuilder
    private var detailContent: some View {
        switch store.selection {
        case .overview, .none:
            FleetOverviewView(store: store)
        case .pools:
            PoolConfigurationView(store: store)
        case .power:
            PowerView(store: store)
        case .maintenance:
            MaintenanceView(store: store)
        case .reports:
            ReportsView(store: store)
        case .miner(let id):
            MinerDetailView(store: store, minerID: id)
                .id(id) // fresh log stream and share history per miner
        }
    }
}

// MARK: - Sidebar rows

/// Background of a sidebar row: a surface step with a hairline when selected, a faint tint on hover.
private struct SidebarRowBackground: ViewModifier {
    let isSelected: Bool
    let isHovered: Bool

    func body(content: Content) -> some View {
        content
            .background(
                isSelected ? Surface.raised : (isHovered ? Color.primary.opacity(0.04) : .clear),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Color.primary.opacity(0.1) : .clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SidebarNavRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let trailing: String?
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(width: 30)

                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let trailing {
                    Text(trailing)
                        .font(.mono(11))
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .modifier(SidebarRowBackground(isSelected: isSelected, isHovered: isHovered))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A miner in the sidebar: its board as a small card with the status LED, name and model, hashrate and temperature.
private struct SidebarMinerRow: View {
    let miner: MinerDevice
    let tempWarningThresholdC: Double
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.redactor) private var redactor
    @State private var isHovered = false

    var body: some View {
        let info = miner.latestInfo
        let isHighTemp = (info?.temp ?? 0) >= tempWarningThresholdC

        Button(action: action) {
            HStack(spacing: 10) {
                DeviceCardView(
                    spec: DeviceCardSpec(miner: miner),
                    width: 30,
                    led: .init(state: miner.connectionState, isHighTemp: isHighTemp)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(redactor.freeText(miner.displayName))
                        .font(.system(size: 13))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(metaLine(info))
                        .font(.mono(11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    // The last values stay in memory while a miner is away; they are not current.
                    if let info, !miner.connectionState.isOffline {
                        Text(MinerFormatting.formatHashrate(info.hashRate))
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.0f °C", info.temp))
                            .foregroundStyle(isHighTemp ? AnyShapeStyle(Signal.warning) : AnyShapeStyle(.tertiary))
                    } else {
                        Text("Offline")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.mono(11))
                .fixedSize()
            }
            .padding(.horizontal, 8)
            .frame(height: 44)
            .modifier(SidebarRowBackground(isSelected: isSelected, isHovered: isHovered))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// `Gamma 601 · BCH`: the model without the family name, then the coin being mined.
    private func metaLine(_ info: MinerSystemInfo?) -> String {
        let spec = DeviceCardSpec(miner: miner)
        let model = spec.model.isEmpty ? miner.hardwareTitle : spec.model
        guard let info else { return model }
        let coin = (info.isDualPoolMining && info.primaryPoolCoin != info.secondaryPoolCoin)
            ? "\(info.primaryPoolCoin.symbol)+\(info.secondaryPoolCoin.symbol)"
            : info.activePoolCoin.symbol
        return "\(model) · \(coin)"
    }
}
