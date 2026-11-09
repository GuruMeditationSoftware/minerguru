import SwiftUI
import Charts
import AppKit

// MARK: - Solo-Mining Probability Card

struct CoinSoloChanceCard: View {
    let summary: FleetCoinMiningSummary
    let timeframe: SoloChanceTimeframe

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardHeaderRow
            HStack(alignment: .top, spacing: 20) {
                soloProbabilityColumn
                    .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(Color.hairline)
                    .frame(width: 1, height: 88)

                blockRewardColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            cardFooterBar
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .nativeCard()
    }

    @ViewBuilder
    private var cardHeaderRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(summary.coin.badgeColor)
                .frame(width: 8, height: 8)

            Text(summary.coin.fullName)
                .font(.system(size: 15, weight: .medium))

            Text(summary.coin.symbol)
                .font(.mono(11))
                .foregroundStyle(.tertiary)

            Spacer()

            Text(MinerFormatting.formatHashrate(summary.totalHashrateGHs))
                .font(.mono(11))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var soloProbabilityColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Solo chance")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text(summary.formattedOddsRatio(for: timeframe))
                .font(.figure(32))
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(summary.formattedProbabilityPercent(for: timeframe))
                .font(.mono(11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Text("Ø 1 block every \(summary.expectedTimePerBlockFormatted)")
                .font(.mono(11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    @ViewBuilder
    private var blockRewardColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Block reward")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(DisplayFormat.decimal(summary.coin.blockSubsidyCoins, maxFractionDigits: 3))
                    .font(.figure(20))
                Text(summary.coin.rawValue)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .padding(.top, 8)

            Text("excluding transaction fees")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var cardFooterBar: some View {
        HStack(spacing: 8) {
            Text(summary.contributingMinersText)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Text("Network diff \(MinerSystemInfo.formatDifficultyNumber(summary.networkDifficulty))")
                .fixedSize()
        }
        .font(.mono(11))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .insetSurface()
    }
}
