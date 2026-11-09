import SwiftUI

// MARK: - Single Log Line Row

struct MinerLogRowView: View {
    let entry: MinerLogEntry
    let timeFormatter: DateFormatter
    @Environment(\.redactor) private var redactor

    private var levelColor: Color {
        if entry.isShareAccepted {
            return Signal.good
        }
        if entry.isShareRejected {
            return Signal.bad
        }
        switch entry.level {
        case .info: return Color.secondary
        case .warning: return Signal.warning
        case .error: return Signal.bad
        case .debug: return .secondary
        }
    }

    private var rowBackground: Color {
        if entry.isShareAccepted {
            return Signal.good.opacity(0.08)
        }
        if entry.isShareRejected || entry.level == .error {
            return Signal.bad.opacity(0.10)
        }
        if entry.level == .warning {
            return Signal.warning.opacity(0.08)
        }
        return Color.clear
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(timeFormatter.string(from: entry.receivedAt))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .fixedSize()

            // Color lives in the chip and row backgrounds; the text stays primary for contrast.
            Text(entry.level.shortLabel)
                .font(.caption2.weight(.medium).monospaced())
                .foregroundStyle(.primary)
                .frame(width: 14, alignment: .center)
                .background(levelColor.opacity(0.28), in: RoundedRectangle(cornerRadius: 3))
                .fixedSize()

            if let tag = entry.componentTag, !tag.isEmpty {
                Text(tag)
                    .font(.caption2.weight(.medium).monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }

            Text(redactor.freeText(entry.message))
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 4))
    }
}
