import SwiftUI

/// Whom the pool slots of a miner pay. Writing the expected address is always the user's decision.
struct PayoutCheckCard: View {
    @ObservedObject var store: MinerStore
    @ObservedObject var alerts: AlertCenter
    let miner: MinerDevice
    let info: MinerSystemInfo
    @Environment(\.redactor) private var redactor
    @State private var failure: String?

    private var slots: [PayoutSlot] { PayoutCheck.slots(of: info, expected: alerts.expectedAddresses) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Payout", systemImage: "checkmark.shield")
                .font(.headline)
            ForEach(slots) { slot in
                HStack(spacing: 10) {
                    Circle().fill(color(slot.verdict)).frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: "\(slot.title) · \(slot.coin.symbol)")
                            .font(.callout.weight(.medium))
                        Text(slot.address.isEmpty ? "–" : redactor.address(slot.address))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(description(slot.verdict))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if slot.verdict == .foreign || slot.verdict == .factoryDefault || slot.verdict == .account,
                       let target = alerts.expectedAddresses[slot.coin.rawValue] {
                        Button("Enter expected address") { apply(target, to: slot) }
                            .controlSize(.small)
                    }
                }
            }
            if let status = blockStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let failure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nativeCard()
    }

    private var blockStatus: LocalizedStringKey? {
        switch info.coinbasePayoutStatus {
        case "verified": "The current block pays this miner."
        case "not_found": "The current block does not contain this miner's address."
        default: nil
        }
    }

    private func color(_ verdict: PayoutVerdict) -> Color {
        switch verdict {
        case .expected: .green
        case .foreign, .factoryDefault: .red
        case .account: .yellow
        case .valid, .empty: .secondary
        }
    }

    private func description(_ verdict: PayoutVerdict) -> LocalizedStringKey {
        switch verdict {
        case .expected: "Matches your expected address"
        case .valid: "Valid address, no expected address set"
        case .foreign: "Differs from your expected address"
        case .factoryDefault: "Firmware default: a block found would not go to you"
        case .account: "Pool account or typing error"
        case .empty: "Nothing entered"
        }
    }

    private func apply(_ address: String, to slot: PayoutSlot) {
        failure = nil
        Task {
            do {
                try await store.applyExpectedAddress(address, slotKey: slot.key, minerID: miner.id)
            } catch is CancellationError {
                // Declined in the confirmation.
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
