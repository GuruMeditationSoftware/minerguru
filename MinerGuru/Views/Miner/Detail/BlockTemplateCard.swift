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
                    pair("Blockhöhe", block.height.formatted())
                    pair("Pool-Kennung", block.poolTag ?? "—")
                    pair("Belohnung", block.totalSats.map { BlockTemplateSummary.formatCoins($0, coin: block.coin) } ?? "—")
                    pair("davon Gebühren", block.feesSats.map { BlockTemplateSummary.formatCoins($0, coin: block.coin) } ?? "—")
                    pair("An deine Adresse", userShareText)
                }
            }

            if let range = block.transactionRange {
                Text("Transaktionen im Block: \(Self.rangeText(range))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Aus der Tiefe des Merkle-Baums: Der Pool nennt nicht die genaue Zahl, nur die Größenordnung.")
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
            ? "Die Vorlage des Pools, an der dein Miner gerade rechnet. Findet er den Block, zahlt die Coinbase so aus wie hier gezeigt. Die übrigen Transaktionen kennt nur der Pool."
            : "Die Vorlage, die der Pool gerade für deine Adresse baut. Der Miner meldet sie nicht, deshalb hat MinerGuru sie selbst beim Pool abgefragt, ohne mitzurechnen. Findet dein Miner den Block, zahlt die Coinbase so aus wie hier gezeigt."
    }

    private func probeFooter(_ probedAt: Date) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text("Vom Mac beim Pool abgefragt, \(probedAt.formatted(date: .omitted, time: .shortened)) Uhr")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 8)
            if isRefreshing {
                ProgressView()
                    .controlSize(.mini)
            } else if let onRefresh {
                Button("Neu abfragen", action: onRefresh)
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
            Text("Signalisiert:")
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
            Text("Empfänger der Belohnung")
                .sectionLabelStyle()

            if block.payoutState == .decodingOff {
                decodingOffHint
            } else if block.outputs.isEmpty {
                Text("Der Miner hat noch keine Empfänger gemeldet.")
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
                    Text("Deine Adresse")
                        .font(.caption2)
                        .foregroundStyle(Signal.good)
                } else if output.isWitnessCommitment {
                    Text("SegWit-Prüfsumme, keine Auszahlung")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if output.isDataOutput {
                    Text("Daten, keine Auszahlung")
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
            Text("\(block.othersCount) weitere Empfänger")
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
                Text("Coinbase-Dekodierung ist für den aktiven Pool aus.")
                    .font(.subheadline.weight(.medium))
                Text("Ohne sie meldet der Miner nicht, wer die Belohnung bekommt, und prüft deine Adresse nicht. Du kannst sie in der Weboberfläche des Miners bei den Pool-Einstellungen einschalten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let onOpenWebInterface {
                    Button("Weboberfläche öffnen", action: onOpenWebInterface)
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
        case "BIP-54": return String(localized: "BIP-54 (Consensus Cleanup): Der Pool zeigt Unterstützung für diese Soft-Fork.")
        case "BIP-110": return String(localized: "BIP-110 (Reduced Data): Der Pool zeigt Unterstützung für diese Soft-Fork.")
        default: return String(localized: "Der Pool zeigt in diesem Block Unterstützung für eine Protokolländerung.")
        }
    }
}

/// "Aktueller Block", with the pool in dual pool mode.
struct BlockCardTitle: View {
    let poolLabel: String?

    var body: some View {
        HStack(spacing: 6) {
            Label("Aktueller Block", systemImage: "cube")
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
        case .verified: return "Deine Adresse ist im Block"
        case .notFound: return "Deine Adresse fehlt"
        case .notApplicable: return "Konto-Pool"
        case .decodingOff: return "Nicht geprüft"
        case .unknown: return "Noch keine Daten"
        }
    }

    private var help: String {
        switch state {
        case .verified:
            return String(localized: "Die Coinbase zahlt an die Adresse aus deinem Pool-User.")
        case .notFound:
            return String(localized: "Im Pool-User steht eine Adresse, aber kein Empfänger im Block passt dazu. Findet dein Miner diesen Block, geht die Belohnung an andere.")
        case .notApplicable:
            return String(localized: "Im Pool-User steht keine Adresse, sondern ein Kontoname. Der Pool zahlt dann selbst aus, im Block steht nur seine Adresse.")
        case .decodingOff:
            return String(localized: "Coinbase-Dekodierung ist aus, der Miner prüft die Auszahlung nicht.")
        case .unknown:
            return String(localized: "Der Miner hat noch keinen Auftrag dekodiert.")
        }
    }
}
