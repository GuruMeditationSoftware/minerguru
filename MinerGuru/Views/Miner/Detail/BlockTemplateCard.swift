import SwiftUI

/// The block the miner is hashing on right now, as far as the coinbase shows it:
/// height, pool tag, reward and who gets it. Comes from the firmware (AxeOS 2.13+) or the Stratum probe.
struct BlockTemplateCard: View {
    let block: BlockTemplateSummary
    var onOpenWebInterface: (() -> Void)? = nil
    /// "Pool 1 · 60 %" when the miner splits its hashrate.
    var poolLabel: String? = nil
    /// Probe results only: fetch the template again.
    var onRefresh: (() -> Void)? = nil
    var isRefreshing = false
    @Environment(\.redactor) private var redactor

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    BlockCardTitle(poolLabel: poolLabel)
                    Spacer(minLength: 8)
                    PayoutStateBadge(state: block.payoutState)
                }
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                GridRow {
                    pair("Block height", block.height.formatted())
                    pair("Pool tag", block.poolTag ?? "—")
                    pair("Reward", block.totalSats.map { BlockTemplateSummary.formatCoins($0, coin: block.coin) } ?? "—")
                    pair("of which fees", block.feesSats.map { BlockTemplateSummary.formatCoins($0, coin: block.coin) } ?? "—")
                    pair("To your address", userShareText)
                }
            }

            if let range = block.transactionRange {
                Text("Transactions in the block: \(Self.rangeText(range))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("From the depth of the merkle tree: the pool does not give the exact number, only the order of magnitude.")
            }

            if !block.signals.isEmpty {
                signalsRow
            }

            Divider()

            outputsSection

            if let probedAt = block.probedAt {
                probeFooter(probedAt)
            }
        }
        .padding(16)
        .nativeCard(highlight: block.payoutState == .notFound ? Signal.bad.opacity(0.6) : nil)
    }

    private var caption: LocalizedStringKey {
        block.probedAt == nil
            ? "The pool's template your miner is working on right now. If it finds the block, the coinbase pays out as shown here. Only the pool knows the other transactions."
            : "The template the pool is building for your address right now. The miner does not report it, so MinerGuru fetched it from the pool itself, without mining. If your miner finds the block, the coinbase pays out as shown here."
    }

    private func probeFooter(_ probedAt: Date) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text("Fetched from the pool by this Mac at \(probedAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 8)
            if isRefreshing {
                ProgressView()
                    .controlSize(.mini)
            } else if let onRefresh {
                Button("Fetch again", action: onRefresh)
                    .controlSize(.small)
            }
        }
    }

    static func rangeText(_ range: ClosedRange<Int>) -> String {
        range.lowerBound == range.upperBound
            ? range.lowerBound.formatted()
            : "\(range.lowerBound.formatted())–\(range.upperBound.formatted())"
    }

    private var userShareText: String {
        guard let userSats = block.userSats, userSats > 0 else { return "—" }
        let amount = BlockTemplateSummary.formatCoins(userSats, coin: block.coin)
        guard let share = block.userShare else { return amount }
        return "\(amount) (\(share.formatted(.percent.precision(.fractionLength(1)))))"
    }

    private var signalsRow: some View {
        HStack(spacing: 8) {
            Text("Signals:")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(block.signals, id: \.self) { signal in
                Text(verbatim: signal)
                    .font(.mono(11))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .insetSurface(cornerRadius: 5)
                    .help(Self.signalHelp(signal))
            }
        }
    }

    @ViewBuilder
    private var outputsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reward recipients")
                .sectionLabelStyle()

            if block.payoutState == .decodingOff {
                decodingOffHint
            } else if block.outputs.isEmpty {
                Text("The miner has not reported any recipients yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(block.outputs.enumerated()), id: \.offset) { _, output in
                        outputRow(output)
                    }
                    if block.othersCount > 0 {
                        othersRow
                    }
                }
            }
        }
    }

    private func outputRow(_ output: CoinbaseOutput) -> some View {
        HStack(spacing: 10) {
            Image(systemName: output.isUserOutput ? "person.fill" : output.isDataOutput ? "text.alignleft" : "building.columns")
                .font(.system(size: 11))
                .foregroundStyle(output.isUserOutput ? Signal.good : Color.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: displayText(for: output))
                    .font(.mono(11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                if output.isUserOutput {
                    Text("Your address")
                        .font(.caption2)
                        .foregroundStyle(Signal.good)
                } else if output.isWitnessCommitment {
                    Text("SegWit commitment, no payout")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if output.isDataOutput {
                    Text("Data, no payout")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 12)

            if output.valueSats > 0 {
                amountColumn(output.valueSats)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .insetSurface()
    }

    private var othersRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "ellipsis")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text("\(block.othersCount) more recipients")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            if block.othersValueSats > 0 {
                amountColumn(block.othersValueSats)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .insetSurface()
    }

    private func amountColumn(_ sats: Double) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(verbatim: BlockTemplateSummary.formatCoins(sats, coin: block.coin))
                .font(.mono(11, weight: .medium))
            if let total = block.totalSats, total > 0 {
                Text(verbatim: (sats / total).formatted(.percent.precision(.fractionLength(1))))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .fixedSize()
    }

    private func displayText(for output: CoinbaseOutput) -> String {
        if output.isWitnessCommitment { return "OP_RETURN" }
        if output.isDataOutput { return output.dataText.map { "OP_RETURN \($0)" } ?? "OP_RETURN" }
        return redactor.address(output.address)
    }

    private var decodingOffHint: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text("Coinbase decoding is off for the active pool.")
                    .font(.subheadline.weight(.medium))
                Text("Without it the miner does not report who gets the reward and does not check your address. You can turn it on in the miner's web interface under the pool settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let onOpenWebInterface {
                    Button("Open web interface", action: onOpenWebInterface)
                        .controlSize(.small)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .insetSurface(cornerRadius: 10)
    }

    private func pair(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .font(.caption.weight(.medium).monospaced())
                .lineLimit(1)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func signalHelp(_ signal: String) -> String {
        switch signal {
        case "BIP-54": return String(localized: "BIP-54 (Consensus Cleanup): the pool signals support for this soft fork.")
        case "BIP-110": return String(localized: "BIP-110 (Reduced Data): the pool signals support for this soft fork.")
        default: return String(localized: "The pool signals support for a protocol change in this block.")
        }
    }
}

/// "Aktueller Block", with the pool in dual pool mode.
struct BlockCardTitle: View {
    let poolLabel: String?

    var body: some View {
        HStack(spacing: 6) {
            Label("Current block", systemImage: "cube")
            if let poolLabel {
                Text(verbatim: "· \(poolLabel)")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 15, weight: .medium))
        .lineLimit(1)
        .fixedSize()
    }
}

/// Whether the block pays the own address, as a dot and quiet text.
private struct PayoutStateBadge: View {
    let state: BlockTemplateSummary.PayoutState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
        }
        .font(.system(size: 11, weight: state == .notFound ? .medium : .regular))
        .foregroundStyle(state == .notFound ? Signal.bad : Color.secondary)
        .lineLimit(1)
        .fixedSize()
        .help(help)
    }

    private var color: Color {
        switch state {
        case .verified: return Signal.good
        case .notFound: return Signal.bad
        case .notApplicable, .decodingOff, .unknown: return Signal.idle
        }
    }

    private var title: LocalizedStringKey {
        switch state {
        case .verified: return "Your address is in the block"
        case .notFound: return "Your address is missing"
        case .notApplicable: return "Account pool"
        case .decodingOff: return "Not checked"
        case .unknown: return "No data yet"
        }
    }

    private var help: String {
        switch state {
        case .verified:
            return String(localized: "The coinbase pays the address from your pool user.")
        case .notFound:
            return String(localized: "Your pool user contains an address, but no recipient in the block matches it. If your miner finds this block, the reward goes to someone else.")
        case .notApplicable:
            return String(localized: "Your pool user is an account name, not an address. The pool pays out itself, so only its own address is in the block.")
        case .decodingOff:
            return String(localized: "Coinbase decoding is off, so the miner does not check the payout.")
        case .unknown:
            return String(localized: "The miner has not decoded a job yet.")
        }
    }
}
