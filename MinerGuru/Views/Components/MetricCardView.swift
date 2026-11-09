import SwiftUI
import AppKit

struct MetricCardView: View {
    let title: LocalizedStringKey
    let value: String
    let unit: String?
    let subtitle: String?
    let systemImage: String
    let tint: Color
    var warning: Bool = false
    var compact: Bool = false

    init(
        title: LocalizedStringKey,
        value: String,
        unit: String? = nil,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color,
        warning: Bool = false,
        compact: Bool = false
    ) {
        self.title = title
        self.value = value
        self.unit = unit
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.warning = warning
        self.compact = compact
    }

    /// Icons and figures stay neutral; only a warning colors the card. `tint` is kept for callers but no longer paints.
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            HStack(spacing: 8) {
                Image(systemName: Self.outlined(systemImage))
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if warning {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(Signal.warning)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.figure(compact ? 20 : 24))
                    .foregroundStyle(warning ? AnyShapeStyle(Signal.bad) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if let unit, !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Text(subtitle.flatMap { $0.isEmpty ? nil : $0.replacingOccurrences(of: " • ", with: " · ") } ?? " ")
                .font(.mono(11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(compact ? 12 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .nativeCard(cornerRadius: 12, highlight: warning ? Signal.bad.opacity(0.45) : nil)
    }

    /// Line variant of a filled SF Symbol, when there is one.
    static func outlined(_ name: String) -> String {
        let candidates = [
            name.replacingOccurrences(of: ".circle.fill", with: ""),
            name.replacingOccurrences(of: ".fill", with: "")
        ]
        return candidates.first { $0 != name && NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil } ?? name
    }
}
