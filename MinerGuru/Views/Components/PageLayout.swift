import SwiftUI

// MARK: - Shared Page Layout (identical geometry for Dashboard & Miner details)

enum PageLayout {
    static let horizontalPadding: CGFloat = 20
    static let verticalPadding: CGFloat = 16
    static let maxContentWidth: CGFloat = 1280
    static let windowMinWidth: CGFloat = 1000
    static let windowMinHeight: CGFloat = 620
}

/// Scroll container that gives every detail page the same padding, maximum width and top alignment,
/// so switching between pages or resizing the window does not shift the content around.
struct PageScrollView<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    init(spacing: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
            .frame(maxWidth: PageLayout.maxContentWidth, alignment: .topLeading)
            .padding(.horizontal, PageLayout.horizontalPadding)
            .padding(.vertical, PageLayout.verticalPadding)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Simple wrapping layout: items flow left to right and wrap to the next line instead of widening the window.
struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 20
    var verticalSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        arrange(sizes: subviews.map { $0.sizeThatFits(.unspecified) }, width: width)
    }

    /// Positions items left to right and wraps to a new line when the next item would exceed `width`.
    func arrange(sizes: [CGSize], width: CGFloat) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for size in sizes {
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + verticalSpacing
                lineHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
            maxX = max(maxX, x - horizontalSpacing)
        }
        return (CGSize(width: maxX, height: y + lineHeight), origins)
    }
}

/// Adaptive grid with equal-height rows and top-aligned, full-width cells.
/// Unlike `LazyVGrid`, cards in one row never end up vertically offset from each other.
struct AdaptiveGrid: Layout {
    var minColumnWidth: CGFloat
    var spacing: CGFloat = 12

    /// Number of columns that fit into `width` (at least 1, at most `itemCount`).
    func columnCount(for width: CGFloat, itemCount: Int) -> Int {
        guard width.isFinite else { return 1 }
        let fitting = max(1, Int(((width + spacing) / (minColumnWidth + spacing)).rounded(.down)))
        return min(fitting, max(1, itemCount))
    }

    func columnWidth(for width: CGFloat, columns: Int) -> CGFloat {
        width.isFinite ? (width - CGFloat(columns - 1) * spacing) / CGFloat(columns) : minColumnWidth
    }

    /// Height of each row = tallest item in that row.
    static func rowHeights(itemHeights: [CGFloat], columns: Int) -> [CGFloat] {
        stride(from: 0, to: itemHeights.count, by: max(1, columns)).map { start in
            itemHeights[start..<min(start + columns, itemHeights.count)].max() ?? 0
        }
    }

    private func layout(width: CGFloat, subviews: Subviews) -> (heights: [CGFloat], columns: Int, colWidth: CGFloat) {
        let columns = columnCount(for: width, itemCount: subviews.count)
        let colWidth = columnWidth(for: width, columns: columns)
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: colWidth, height: nil)).height }
        return (Self.rowHeights(itemHeights: heights, columns: columns), columns, colWidth)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? minColumnWidth
        let l = layout(width: width, subviews: subviews)
        let height = l.heights.reduce(0, +) + CGFloat(max(0, l.heights.count - 1)) * spacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let l = layout(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for (row, rowHeight) in l.heights.enumerated() {
            for col in 0..<l.columns {
                let index = row * l.columns + col
                guard index < subviews.count else { break }
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + CGFloat(col) * (l.colWidth + spacing), y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: l.colWidth, height: rowHeight)
                )
            }
            y += rowHeight + spacing
        }
    }
}
