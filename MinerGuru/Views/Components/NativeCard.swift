import SwiftUI
import AppKit

// MARK: - Card style

extension View {
    /// Graphite card: the card surface with a hairline border.
    /// Pass `highlight` only for state that needs attention (warning, selection).
    func nativeCard(cornerRadius: CGFloat = 14, highlight: Color? = nil) -> some View {
        self
            .background(Surface.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(highlight ?? Color.hairline, lineWidth: 1)
            )
    }

    /// Inset inside a card, e.g. a pool line or a code block: one surface step up, inner radius.
    func insetSurface(cornerRadius: CGFloat = 8) -> some View {
        background(Surface.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
