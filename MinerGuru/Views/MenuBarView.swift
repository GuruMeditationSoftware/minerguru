import SwiftUI
import AppKit

struct MenuBarView: View {
    @ObservedObject var store: MinerStore
    let dock: DockPresence
    @Environment(\.openWindow) private var openWindow

    /// The popover grows with its miner list until it would run off the screen; from there on the list
    /// scrolls between the fixed summary and the buttons, which therefore always stay reachable.
    @State private var screenHeight: CGFloat = NSScreen.main?.visibleFrame.height ?? 800
    @State private var topHeight: CGFloat = 0
    @State private var bottomHeight: CGFloat = 0
    @State private var rowsHeight: CGFloat?

    private static let padding: CGFloat = 16
    private static let spacing: CGFloat = 12
    private static let rowSpacing: CGFloat = 8
    /// Free room kept between the popover and the bottom of the screen (or the Dock).
    private static let screenMargin: CGFloat = 40
    /// The list never shrinks below this, even on a very small screen.
    private static let minimumListHeight: CGFloat = 120

    init(store: MinerStore, dock: DockPresence) {
        self.store = store
        self.dock = dock
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            VStack(alignment: .leading, spacing: Self.spacing) {
                header
                if !store.miners.isEmpty {
                    summary
                    Divider()
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topHeight = $0 }

            if store.miners.isEmpty {
                Text("Noch keine Miner eingerichtet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                minerList
            }

            VStack(spacing: Self.spacing) {
                Divider()
                actions
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottomHeight = $0 }
        }
        .padding(Self.padding)
        .frame(width: 340)
        .background(ScreenHeightReader(height: $screenHeight))
    }

    // MARK: - Parts

    private var header: some View {
        HStack {
            MinerGuruMark(size: 14)
            Text("MinerGuru")
                .font(.system(size: 15, weight: .medium))
            Spacer()
            HStack(spacing: 6) {
                StatusBlock(state: store.onlineMiners.isEmpty ? .offline(reason: "") : .online, size: 7)
                Text("\(store.onlineMiners.count)/\(store.miners.count) Online")
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.medium))
        }
    }

    private var summary: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hashrate")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(MinerFormatting.formatHashrate(store.totalHashrateGHs))
                    .font(.subheadline.weight(.medium).monospacedDigit())
            }
            Divider().frame(height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("Leistung")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f W", store.totalPowerWatts))
                    .font(.subheadline.weight(.medium).monospacedDigit())
            }
            Divider().frame(height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ø Ping")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(MinerFormatting.formatLatency(store.averagePoolLatencyMs))
                    .font(.subheadline.weight(.medium).monospacedDigit())
            }
            Divider().frame(height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("Best Diff")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(MinerSystemInfo.formatSessionBest(store.bestSessionMiner?.difficulty))
                    .font(.subheadline.weight(.medium).monospacedDigit())
            }
        }
        // Four figures share 280 points; a large fleet's hashrate shrinks a little rather than end in "…".
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .help("Best Diff: höchste Difficulty seit dem letzten Neustart der Miner")
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }

    /// The scroll view reaches into the side padding, so its scroller sits at the popover's edge
    /// instead of on top of the figures.
    private var minerList: some View {
        ScrollView(.vertical) {
            VStack(spacing: Self.rowSpacing) {
                ForEach(store.miners) { miner in
                    MenuBarMinerRow(miner: miner, tempWarningThresholdC: store.tempWarningThresholdC)
                }
            }
            .padding(.horizontal, Self.padding)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowsHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: listHeight)
        .padding(.horizontal, -Self.padding)
    }

    private var listHeight: CGFloat {
        // Before the first measurement: a rough guess, so the popover does not open with an empty list.
        let rows = rowsHeight ?? CGFloat(store.miners.count) * (MenuBarMinerRow.estimatedHeight + Self.rowSpacing)
        let fixed = topHeight + bottomHeight + 2 * Self.spacing + 2 * Self.padding
        let available = max(screenHeight - Self.screenMargin - fixed, Self.minimumListHeight)
        return min(rows, available)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                dock.showDockIcon() // the app runs without Dock icon while no window is open
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Dashboard öffnen", systemImage: "macwindow")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button {
                Task { await store.refreshAllMiners() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Jetzt aktualisieren")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("MinerGuru beenden")
        }
    }
}

/// One miner in the menu bar popover: name, coin and address on the left, figures on the right.
private struct MenuBarMinerRow: View {
    let miner: MinerDevice
    let tempWarningThresholdC: Double
    @Environment(\.redactor) private var redactor

    /// Three lines of caption text plus padding; only used until the real rows have been measured.
    static let estimatedHeight: CGFloat = 50

    var body: some View {
        let info = miner.latestInfo
        HStack(spacing: 8) {
            ConnectionStatusDot(
                state: miner.connectionState,
                isHighTemp: (info?.temp ?? 0) >= tempWarningThresholdC
            )
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(miner.displayName)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    if let info {
                        let coinTag = (info.isDualPoolMining && info.primaryPoolCoin != info.secondaryPoolCoin)
                            ? "\(info.primaryPoolCoin.symbol)+\(info.secondaryPoolCoin.symbol)"
                            : info.activePoolCoin.symbol
                        HStack(spacing: 4) {
                            Circle()
                                .fill(info.activePoolCoin.badgeColor)
                                .frame(width: 6, height: 6)
                            Text(coinTag)
                                .font(.mono(11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Text("\(miner.hardwareTitle) · \(redactor.ip(miner.ipAddress))")
                    .font(.mono(11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            if let info {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(MinerFormatting.formatHashrate(info.hashRate))
                        .font(.caption.weight(.medium).monospacedDigit())
                    HStack(spacing: 4) {
                        Text(String(format: "%.0f°C", info.temp))
                        if let ping = miner.activePoolLatencyMs {
                            Text("• \(String(format: "%.0fms", ping))")
                        }
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    Text("Best \(info.sessionBestDiffText)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Offline")
                    .font(.mono(11))
                    .foregroundStyle(Signal.bad)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Reports the usable height of the screen the popover opens on (without menu bar and Dock).
/// It asks again whenever the popover is shown, so a second display with another size is followed.
private struct ScreenHeightReader: NSViewRepresentable {
    @Binding var height: CGFloat

    func makeNSView(context: Context) -> ReaderView { ReaderView() }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.onChange = { newHeight in
            if abs(height - newHeight) > 0.5 { height = newHeight }
        }
    }

    final class ReaderView: NSView {
        var onChange: ((CGFloat) -> Void)?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let center = NotificationCenter.default
            observers.forEach(center.removeObserver)
            observers = []
            guard let window else { return }
            let names: [(Notification.Name, AnyObject?)] = [
                (NSWindow.didBecomeKeyNotification, window),
                (NSWindow.didChangeScreenNotification, window),
                (NSApplication.didChangeScreenParametersNotification, nil),
            ]
            observers = names.map { name, object in
                center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.report() }
                }
            }
            report()
        }

        private func report() {
            guard let screen = window?.screen ?? NSScreen.main else { return }
            let height = screen.visibleFrame.height
            // Not while SwiftUI is still laying out the view that holds this reader.
            Task { @MainActor in self.onChange?(height) }
        }
    }
}
