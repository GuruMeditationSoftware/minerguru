import SwiftUI

/// Block cards for miners whose firmware reports no block data: one per pool, filled by the
/// Stratum probe while the page is open. With the probe off, a short hint where to switch it on.
struct ProbedBlockSection: View {
    @ObservedObject var probes: BlockProbeStore
    let targets: [BlockProbeTarget]
    let isEnabled: Bool

    var body: some View {
        if targets.isEmpty {
            EmptyView()
        } else if isEnabled {
            VStack(spacing: 16) {
                ForEach(targets, id: \.self) { target in
                    card(for: target)
                }
            }
            .task(id: targets) {
                // Throttled in the store; the loop only picks up the next round after five minutes.
                while !Task.isCancelled {
                    for target in targets { probes.refresh(target) }
                    try? await Task.sleep(for: .seconds(60))
                }
            }
        } else {
            ProbeOffHint()
        }
    }

    @ViewBuilder
    private func card(for target: BlockProbeTarget) -> some View {
        let label = Self.label(for: target, count: targets.count)
        let isRunning = probes.running.contains(target)
        switch probes.entries[target]?.state ?? .loading {
        case .loaded(let block):
            BlockTemplateCard(
                block: block,
                poolLabel: label,
                onRefresh: { probes.refresh(target, force: true) },
                isRefreshing: isRunning
            )
        case .loading:
            ProbeStatusCard(poolLabel: label, host: target.host) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("MinerGuru fragt den Pool nach seiner Vorlage …")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .failed(let message):
            ProbeStatusCard(poolLabel: label, host: target.host) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Signal.warning)
                    Text(verbatim: message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if isRunning {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Button("Erneut versuchen") { probes.refresh(target, force: true) }
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private static func label(for target: BlockProbeTarget, count: Int) -> String? {
        guard count > 1 || target.sharePercent != nil else { return nil }
        let number = target.slot == .primary ? 1 : 2
        if let share = target.sharePercent {
            return String(localized: "Pool \(number) · \(share) %")
        }
        return String(localized: "Pool \(number)")
    }
}

/// Card frame while the probe runs or after it failed.
private struct ProbeStatusCard<Content: View>: View {
    let poolLabel: String?
    let host: String
    @ViewBuilder let content: Content
    @Environment(\.redactor) private var redactor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                BlockCardTitle(poolLabel: poolLabel)
                Spacer(minLength: 8)
                Text(verbatim: redactor.freeText(host))
                    .font(.mono(11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nativeCard()
    }
}

/// Points to the opt-in setting instead of showing nothing.
private struct ProbeOffHint: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "cube")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Blockansicht")
                    .font(.subheadline.weight(.medium))
                Text("Dieser Miner meldet nicht, an welchem Block er rechnet. MinerGuru kann die Vorlage selbst beim Pool abfragen und prüfen, ob deine Adresse darin steht.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            OpenSettingsButton {
                Text("In den Einstellungen einschalten")
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nativeCard()
    }
}
