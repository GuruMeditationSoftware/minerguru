import SwiftUI

/// Hardware model as quiet text. The board itself is shown by `DeviceCardView`.
struct HardwareBadgeView: View {
    let title: String

    init(title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct LatencyBadgeView: View {
    let latencyMs: Double?
    var compact: Bool = false

    init(latencyMs: Double?, compact: Bool = false) {
        self.latencyMs = latencyMs
        self.compact = compact
    }

    private var quality: LatencyQuality {
        LatencyQuality.evaluate(latencyMs)
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(quality.color)
                .frame(width: 6, height: 6)

            Text(MinerFormatting.formatLatency(latencyMs))
                .font(.mono(11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !compact, latencyMs != nil {
                Text(quality.label)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// Connection state of a miner as the app's status block.
struct ConnectionStatusDot: View {
    let state: MinerConnectionState
    let isHighTemp: Bool

    init(state: MinerConnectionState, isHighTemp: Bool = false) {
        self.state = state
        self.isHighTemp = isHighTemp
    }

    private var accessibilityText: Text {
        switch state {
        case .online:
            return isHighTemp ? Text("Online, temperature high") : Text("Online")
        case .checking, .unknown:
            return Text("Checking connection")
        case .offline:
            return Text("Offline")
        }
    }

    var body: some View {
        StatusBlock(state: state, isHighTemp: isHighTemp, size: 8)
            .frame(width: 14, height: 14)
            .help(accessibilityText)
            .accessibilityElement()
            .accessibilityLabel(accessibilityText)
    }
}

extension MinedCoin {
    /// Each coin keeps its own color, shown only as a small dot next to its symbol.
    var badgeColor: Color {
        switch self {
        case .btc:
            return Color.dynamic(light: 0xd9780a, dark: 0xf0a03c)
        case .bch:
            return Color.dynamic(light: 0x14a06c, dark: 0x3ecf8e)
        case .dgb:
            return Color.dynamic(light: 0x2a78d6, dark: 0x5aa2f5)
        case .xec:
            return Color.dynamic(light: 0x0e9f9f, dark: 0x3cc9c9)
        case .bsv:
            return Color.dynamic(light: 0xb58a06, dark: 0xf5c04a)
        case .ppc:
            return Color.dynamic(light: 0x4f9a2a, dark: 0x7ccf5a)
        case .nmc:
            return Color.dynamic(light: 0x5b6ad0, dark: 0x8d98f0)
        case .fb:
            return Color.dynamic(light: 0x7c5ce0, dark: 0xa48af5)
        case .unknown:
            return Signal.idle
        }
    }
}

struct CoinBadgeView: View {
    let coin: MinedCoin
    var percentage: Int? = nil
    var showFullName: Bool = false
    var compact: Bool = false

    init(
        coin: MinedCoin,
        percentage: Int? = nil,
        showFullName: Bool = false,
        compact: Bool = false
    ) {
        self.coin = coin
        self.percentage = percentage
        self.showFullName = showFullName
        self.compact = compact
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(coin.badgeColor)
                .frame(width: 6, height: 6)
            Text(coin.symbol)
                .font(.mono(11, weight: .medium))
                .foregroundStyle(.secondary)
            if showFullName && coin != .unknown {
                Text(coin.fullName)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            if let percentage {
                Text("\(percentage) %")
                    .font(.mono(11))
                    .foregroundStyle(.tertiary)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct MinerActiveCoinsBadgeView: View {
    let info: MinerSystemInfo
    var compact: Bool = false

    init(info: MinerSystemInfo, compact: Bool = false) {
        self.info = info
        self.compact = compact
    }

    var body: some View {
        if info.isDualPoolMining {
            if info.primaryPoolCoin != info.secondaryPoolCoin {
                HStack(spacing: 8) {
                    CoinBadgeView(
                        coin: info.primaryPoolCoin,
                        percentage: info.dualPoolPrimaryPercent,
                        compact: compact
                    )
                    CoinBadgeView(
                        coin: info.secondaryPoolCoin,
                        percentage: info.dualPoolSecondaryPercent,
                        compact: compact
                    )
                }
                .fixedSize(horizontal: true, vertical: false)
            } else {
                CoinBadgeView(
                    coin: info.primaryPoolCoin,
                    showFullName: !compact,
                    compact: compact
                )
            }
        } else {
            CoinBadgeView(
                coin: info.activePoolCoin,
                showFullName: !compact,
                compact: compact
            )
        }
    }
}

/// Which pool a miner uses right now, as quiet text. Only the fallback pool gets a warning dot.
struct PoolModeBadgeView: View {
    let info: MinerSystemInfo
    var compact: Bool = false

    init(info: MinerSystemInfo, compact: Bool = false) {
        self.info = info
        self.compact = compact
    }

    var body: some View {
        Group {
            if info.isDualPoolMining {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 11))
                    Text(
                        compact
                            ? "Dual \(info.dualPoolPrimaryPercent)/\(info.dualPoolSecondaryPercent)"
                            : "Dual pool \(info.dualPoolPrimaryPercent) / \(info.dualPoolSecondaryPercent) %"
                    )
                }
                .foregroundStyle(.secondary)
            } else if info.isUsingFallbackStratum {
                HStack(spacing: 6) {
                    Circle().fill(Signal.warning).frame(width: 6, height: 6)
                    Text(compact ? "Fallback" : "Fallback pool active")
                }
                .foregroundStyle(.secondary)
            } else {
                Text(compact ? "Primary" : "Primary pool active")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 11))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}
