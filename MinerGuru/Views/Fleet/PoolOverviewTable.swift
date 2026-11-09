import SwiftUI
import AppKit

/// Native table comparing the active pool, worker and latency of every miner.
struct PoolOverviewTable: View {
    @ObservedObject var store: MinerStore
    @Environment(\.redactor) private var redactor


    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Pool-Verbindungen & Latenzen", systemImage: "network")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Live-Vergleich aller Miner")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Table(store.miners, selection: poolTableSelection) {
                TableColumn("Miner") { miner in
                    poolMinerCell(miner)
                }
                .width(min: 110, ideal: 140)

                TableColumn("Aktiver Pool-Server") { miner in
                    poolServerCell(miner)
                }
                .width(min: 170, ideal: 260)

                TableColumn("Worker / Wallet") { miner in
                    poolWorkerCell(miner)
                }
                .width(min: 120, ideal: 220)

                TableColumn("Best Diff (Session)") { miner in
                    poolSessionBestCell(miner)
                }
                .width(min: 90, ideal: 120, max: 150)

                TableColumn("Modus") { miner in
                    if let info = miner.latestInfo {
                        PoolModeBadgeView(info: info, compact: true)
                    } else {
                        Text("Offline")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .width(min: 90, ideal: 110, max: 130)

                TableColumn("Pool-Latenz") { miner in
                    poolLatencyCell(miner)
                }
                .width(min: 90, ideal: 110, max: 130)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .scrollDisabled(true)
            .frame(height: poolTableHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
        }
    }

    // MARK: Pool table cells

    /// Rows with one pool line vs. two lines (dual-pool miners); the table cannot size itself to its rows.
    private static let poolTableRowHeight: CGFloat = 37
    private static let poolTableDualRowHeight: CGFloat = 52
    private static let poolTableHeaderHeight: CGFloat = 28

    private var poolTableHeight: CGFloat {
        let rows = store.miners.reduce(CGFloat(0)) { height, miner in
            height + (miner.latestInfo?.isDualPoolMining == true ? Self.poolTableDualRowHeight : Self.poolTableRowHeight)
        }
        return Self.poolTableHeaderHeight + rows + 8
    }

    private var poolTableSelection: Binding<UUID?> {
        Binding(
            get: { nil },
            set: { id in
                if let id { store.selection = .miner(id) }
            }
        )
    }

    private func poolMinerCell(_ miner: MinerDevice) -> some View {
        HStack(spacing: 8) {
            ConnectionStatusDot(
                state: miner.connectionState,
                isHighTemp: (miner.latestInfo?.temp ?? 0) >= store.tempWarningThresholdC
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(redactor.freeText(miner.displayName))
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(redactor.ip(miner.ipAddress))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospaced()
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func poolServerCell(_ miner: MinerDevice) -> some View {
        if let info = miner.latestInfo, info.isDualPoolMining {
            VStack(alignment: .leading, spacing: 3) {
                poolEndpointLine(coin: info.primaryPoolCoin, percentage: info.dualPoolPrimaryPercent, endpoint: info.primaryPoolEndpoint)
                poolEndpointLine(coin: info.secondaryPoolCoin, percentage: info.dualPoolSecondaryPercent, endpoint: info.fallbackPoolEndpoint)
            }
        } else if let info = miner.latestInfo {
            poolEndpointLine(coin: info.activePoolCoin, percentage: nil, endpoint: info.activePoolEndpoint)
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }

    private func poolEndpointLine(coin: MinedCoin, percentage: Int?, endpoint: String) -> some View {
        HStack(spacing: 6) {
            CoinBadgeView(coin: coin, percentage: percentage, compact: true)
            Text(endpoint)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private func poolWorkerCell(_ miner: MinerDevice) -> some View {
        if let info = miner.latestInfo, info.isDualPoolMining {
            VStack(alignment: .leading, spacing: 3) {
                poolUserText(info.stratumUser)
                poolUserText(info.fallbackStratumUser)
            }
        } else if let info = miner.latestInfo {
            poolUserText(info.activePoolUser)
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }

    private func poolUserText(_ user: String) -> some View {
        Text(user.isEmpty ? "—" : redactor.stratumUser(user))
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    @ViewBuilder
    private func poolSessionBestCell(_ miner: MinerDevice) -> some View {
        if let info = miner.latestInfo, info.isDualPoolMining {
            VStack(alignment: .leading, spacing: 3) {
                sessionBestText(info.primaryPoolSessionBestDiff)
                sessionBestText(info.secondaryPoolSessionBestDiff)
            }
        } else if let info = miner.latestInfo {
            sessionBestText(info.sessionBestDiff)
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }

    private func sessionBestText(_ value: Double?) -> some View {
        Text(MinerSystemInfo.formatSessionBest(value))
            .font(.caption.weight(.medium).monospacedDigit())
    }

    @ViewBuilder
    private func poolLatencyCell(_ miner: MinerDevice) -> some View {
        if let info = miner.latestInfo, info.isDualPoolMining {
            let p1 = miner.primaryPoolEffectiveLatencyMs.map { String(format: "%.0f", $0) } ?? "—"
            let p2 = miner.secondaryPoolEffectiveLatencyMs.map { String(format: "%.0f", $0) } ?? "—"
            VStack(alignment: .leading, spacing: 2) {
                LatencyBadgeView(latencyMs: miner.activePoolLatencyMs, compact: true)
                Text("P1 \(p1) • P2 \(p2) ms")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            LatencyBadgeView(latencyMs: miner.activePoolLatencyMs, compact: true)
        }
    }
}
