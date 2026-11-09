import SwiftUI
import AppKit

struct PoolInformationCard: View {
    let miner: MinerDevice
    @Environment(\.redactor) private var redactor
    let onConfigurePool: () -> Void
    let onRefreshLatency: () -> Void

    @State private var copiedUser = false

    init(
        miner: MinerDevice,
        onConfigurePool: @escaping () -> Void,
        onRefreshLatency: @escaping () -> Void
    ) {
        self.miner = miner
        self.onConfigurePool = onConfigurePool
        self.onRefreshLatency = onRefreshLatency
    }

    var body: some View {
        let info = miner.latestInfo

        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Label("Pool & Stratum Connection", systemImage: "globe.europe.africa.fill")
                        .font(.system(size: 15, weight: .medium))
                        .lineLimit(1)
                        .fixedSize()

                    Spacer(minLength: 8)

                    HStack(spacing: 8) {
                        Button {
                            onRefreshLatency()
                        } label: {
                            Label("Check latency", systemImage: "waveform.path.ecg")
                                .labelStyle(.iconOnly)
                        }
                        .help("Check latency")

                        Button {
                            onConfigurePool()
                        } label: {
                            Label("Configure Pool…", systemImage: "slider.horizontal.3")
                                .labelStyle(.iconOnly)
                        }
                        .help("Configure Pool…")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .fixedSize()
                }

                if let info {
                    FlowLayout(horizontalSpacing: 8, verticalSpacing: 6) {
                        PoolModeBadgeView(info: info)
                        MinerActiveCoinsBadgeView(info: info)
                    }
                }
            }

            Divider()

            if let info {
                let isDual = info.isDualPoolMining
                let usingFallback = info.isUsingFallbackStratum

                // If Dual-Pool Mining is active, show visual Hashrate Split Bar
                if isDual {
                    dualPoolSplitBanner(info: info)
                }

                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                    GridRow {
                        poolSlotColumn(
                            title: isDual
                                ? "Pool 1 (\(info.dualPoolPrimaryPercent)% • ~\(MinerFormatting.formatHashrate(info.hashRate * Double(info.dualPoolPrimaryPercent) / 100.0)))"
                                : String(localized: "Primary Stratum Pool"),
                            coin: info.primaryPoolCoin,
                            isActive: isDual ? (info.primaryPoolStatus?.connected ?? true) : !usingFallback,
                            accentColor: isDual ? info.primaryPoolCoin.badgeColor : Accent.color,
                            host: info.stratumURL,
                            port: info.stratumPort,
                            user: info.stratumUser,
                            poolStatus: info.primaryPoolStatus,
                            networkDiffFormatted: info.primaryPoolNetworkDiffFormatted,
                            sessionBestDiff: info.primaryPoolSessionBestDiff,
                            directLatencyMs: miner.poolLatency?.primaryPoolDirectMs,
                            minerLatencyMs: info.primaryPoolMinerLatencyMs
                        )

                        poolSlotColumn(
                            title: isDual
                                ? "Pool 2 (\(info.dualPoolSecondaryPercent)% • ~\(MinerFormatting.formatHashrate(info.hashRate * Double(info.dualPoolSecondaryPercent) / 100.0)))"
                                : String(localized: "Fallback Stratum Pool"),
                            coin: info.secondaryPoolCoin,
                            isActive: isDual ? (info.secondaryPoolStatus?.connected ?? true) : usingFallback,
                            accentColor: isDual ? info.secondaryPoolCoin.badgeColor : Accent.color,
                            host: info.fallbackStratumURL,
                            port: info.fallbackStratumPort,
                            user: info.fallbackStratumUser,
                            poolStatus: info.secondaryPoolStatus,
                            networkDiffFormatted: info.secondaryPoolNetworkDiffFormatted,
                            sessionBestDiff: info.secondaryPoolSessionBestDiff,
                            directLatencyMs: miner.poolLatency?.fallbackPoolDirectMs,
                            minerLatencyMs: info.secondaryPoolMinerLatencyMs
                        )
                    }
                }

                Divider()

                // Bottom summary strip
                HStack(spacing: 20) {
                    if let worker = info.activeWorkerName {
                        HStack(spacing: 6) {
                            Image(systemName: "person.badge.key.fill")
                                .foregroundStyle(.secondary)
                            Text("Worker:")
                                .foregroundStyle(.secondary)
                            Text(worker)
                                .fontWeight(.medium)
                                .monospaced()
                        }
                        .font(.caption)
                        .fixedSize()
                    }

                    if isDual {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.branch")
                                .foregroundStyle(.secondary)
                            Text("Dual mining:")
                                .foregroundStyle(.secondary)
                            Text("\(info.primaryPoolCoin.symbol) (\(info.dualPoolPrimaryPercent)%) + \(info.secondaryPoolCoin.symbol) (\(info.dualPoolSecondaryPercent)%)")
                                .fontWeight(.medium)
                        }
                        .font(.caption)
                        .fixedSize()
                    } else if let poolDiff = info.activePoolDifficulty, poolDiff > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "gauge.with.dots.needle.50percent")
                                .foregroundStyle(.secondary)
                            Text("Pool difficulty:")
                                .foregroundStyle(.secondary)
                            Text(MinerSystemInfo.formatDifficultyNumber(poolDiff))
                                .fontWeight(.medium)
                                .monospacedDigit()
                        }
                        .font(.caption)
                        .fixedSize()
                    }

                    Spacer()

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(info.stratumUser, forType: .string)
                        copiedUser = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copiedUser = false
                        }
                    } label: {
                        Label(copiedUser ? "Copied!" : "Copy pool user", systemImage: copiedUser ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                }
            } else {
                Text("No pool information available (miner offline).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .nativeCard()
    }

    @ViewBuilder
    private func dualPoolSplitBanner(info: MinerSystemInfo) -> some View {
        let p1 = info.dualPoolPrimaryPercent
        let p2 = info.dualPoolSecondaryPercent
        let host1 = StratumHost.clean(info.stratumURL, keepPort: true)
        let host2 = StratumHost.clean(info.fallbackStratumURL, keepPort: true)
        let c1 = info.primaryPoolCoin
        let c2 = info.secondaryPoolCoin

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    CoinBadgeView(coin: c1, percentage: p1, compact: true)
                    Text("Pool 1: \(host1)")
                        .font(.caption.weight(.medium))
                }
                Spacer()
                Text("Dual-pool hashrate split")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 6) {
                    Text("Pool 2: \(host2)")
                        .font(.caption.weight(.medium))
                    CoinBadgeView(coin: c2, percentage: p2, compact: true)
                }
            }

            GeometryReader { geo in
                let totalW = max(10, geo.size.width)
                let w1 = max(8, totalW * CGFloat(p1) / 100.0)
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(c1.badgeColor)
                        .frame(width: w1)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(c2.badgeColor)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 8)
        }
        .padding(12)
        .background(Surface.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func poolSlotColumn(
        title: String,
        coin: MinedCoin,
        isActive: Bool,
        accentColor: Color,
        host: String,
        port: Int,
        user: String,
        poolStatus: MinerStratumPoolStatus?,
        networkDiffFormatted: String?,
        sessionBestDiff: Double?,
        directLatencyMs: Double?,
        minerLatencyMs: Double?
    ) -> some View {
        let effectiveLatency = minerLatencyMs ?? directLatencyMs
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(horizontalSpacing: 8, verticalSpacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isActive ? Signal.good : Color.secondary.opacity(0.4))
                        .frame(width: 8, height: 8)
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                }
                .fixedSize()
                if !host.isEmpty {
                    CoinBadgeView(coin: coin, showFullName: true, compact: true)
                }
                LatencyBadgeView(latencyMs: effectiveLatency)
            }

            HStack(spacing: 6) {
                Text("Server:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)
                Text(verbatim: host.isEmpty ? "—" : "\(host):\(port)")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                    .textSelection(.enabled)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Text("User:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)
                Text(user.isEmpty ? "—" : redactor.stratumUser(user))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            if let poolStatus {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Shares:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)

                    FlowLayout(horizontalSpacing: 10, verticalSpacing: 2) {
                        if let acc = poolStatus.accepted {
                            let rej = poolStatus.rejected ?? 0
                            Text("\(acc.formatted()) ok / \(rej) rej")
                                .font(.caption.weight(.medium).monospacedDigit())
                        }

                        if let diff = poolStatus.poolDifficulty, diff > 0 {
                            Text("• Pool diff: \(MinerSystemInfo.formatDifficultyNumber(diff))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        if let netDiff = networkDiffFormatted {
                            Text("• Net diff: \(netDiff)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else if let netDiff = networkDiffFormatted {
                HStack(spacing: 10) {
                    Text("Network:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    Text("Net diff: \(netDiff) (\(coin.fullName))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                Text("Best Diff:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)
                Text(MinerSystemInfo.formatSessionBest(sessionBestDiff))
                    .font(.caption.weight(.medium).monospacedDigit())
                Text("since restart")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Text("Latency:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)

                if let minerLatencyMs, minerLatencyMs > 0 {
                    Text("Miner RTT: \(MinerFormatting.formatLatency(minerLatencyMs))")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if let directLatencyMs, directLatencyMs > 0 {
                    Text("TCP ping: \(MinerFormatting.formatLatency(directLatencyMs))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if minerLatencyMs == nil && directLatencyMs == nil {
                    Text("Measuring…")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isActive ? Surface.raised : Surface.raised.opacity(0.4),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isActive ? Color.primary.opacity(0.1) : Color.clear, lineWidth: 1)
        )
    }
}
