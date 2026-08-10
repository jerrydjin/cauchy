import SwiftUI

/// One measured token: how big it is, and how far its text baseline sits below
/// its top edge. Math and text of the same height do not share a baseline, so
/// the baseline has to be carried through layout explicitly.
struct InlineFlowToken: Equatable {
    let size: CGSize
    let baseline: CGFloat

    init(size: CGSize, baseline: CGFloat) {
        self.size = size
        self.baseline = baseline
    }

    /// Tokens with no baseline of their own sit on their bottom edge.
    init(size: CGSize) {
        self.init(size: size, baseline: size.height)
    }
}

struct InlineFlowLayoutPlacement: Equatable {
    let x: CGFloat
    let y: CGFloat
    let size: CGSize
}

struct InlineFlowLayoutResult: Equatable {
    let size: CGSize
    let placements: [InlineFlowLayoutPlacement]
}

enum InlineFlowLayoutEngine {
    /// Wraps tokens into rows and sits every token in a row on one shared
    /// baseline, so inline math lines up with the words around it instead of
    /// floating above them.
    static func layout(
        tokens: [InlineFlowToken],
        maxWidth: CGFloat,
        horizontalSpacing: CGFloat = 4,
        verticalSpacing: CGFloat = 4
    ) -> InlineFlowLayoutResult {
        let maxWidth = max(maxWidth, 1)

        // Pass 1: break into rows.
        var rows: [[(index: Int, x: CGFloat, token: InlineFlowToken)]] = []
        var row: [(index: Int, x: CGFloat, token: InlineFlowToken)] = []
        var x: CGFloat = 0

        for (index, token) in tokens.enumerated() {
            if x > 0, token.size.width > max(0, maxWidth - x) {
                rows.append(row)
                row = []
                x = 0
            }
            row.append((index, x, token))
            x += token.size.width + horizontalSpacing
        }
        if !row.isEmpty { rows.append(row) }

        // Pass 2: place each row on its own baseline.
        var placements = Array(
            repeating: InlineFlowLayoutPlacement(x: 0, y: 0, size: .zero),
            count: tokens.count
        )
        var resultWidth: CGFloat = 0
        var y: CGFloat = 0

        for row in rows {
            let ascent = row.map(\.token.baseline).max() ?? 0
            let descent = row.map { $0.token.size.height - $0.token.baseline }.max() ?? 0

            for entry in row {
                placements[entry.index] = InlineFlowLayoutPlacement(
                    x: entry.x,
                    y: y + ascent - entry.token.baseline,
                    size: entry.token.size
                )
                resultWidth = max(resultWidth, min(entry.x + entry.token.size.width, maxWidth))
            }

            y += ascent + descent + verticalSpacing
        }

        return InlineFlowLayoutResult(
            size: CGSize(width: min(resultWidth, maxWidth), height: max(0, y - verticalSpacing)),
            placements: placements
        )
    }
}

struct InlineFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 4
    var verticalSpacing: CGFloat = 4

    /// The wrap result depends only on the proposed width, and measuring the
    /// subviews (sizeThatFits per token, twice on wraps) dominates the cost.
    /// Reusing the result between sizeThatFits and placeSubviews halves the
    /// measurement work; SwiftUI invalidates via updateCache when subviews change.
    struct LayoutCache {
        var width: CGFloat?
        var result: InlineFlowLayoutResult?
    }

    func makeCache(subviews: Subviews) -> LayoutCache {
        LayoutCache()
    }

    func updateCache(_ cache: inout LayoutCache, subviews: Subviews) {
        cache.width = nil
        cache.result = nil
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout LayoutCache) -> CGSize {
        cachedLayout(width: proposal.width, subviews: subviews, cache: &cache).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout LayoutCache) {
        let result = cachedLayout(width: bounds.width, subviews: subviews, cache: &cache)

        for (index, placement) in result.placements.enumerated() {
            guard index < subviews.count else { break }
            subviews[index].place(
                at: CGPoint(x: bounds.minX + placement.x, y: bounds.minY + placement.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(placement.size)
            )
        }
    }

    private func cachedLayout(width: CGFloat?, subviews: Subviews, cache: inout LayoutCache) -> InlineFlowLayoutResult {
        if let result = cache.result, cache.width == width {
            return result
        }
        let result = layout(width: width, subviews: subviews)
        cache.width = width
        cache.result = result
        return result
    }

    private func layout(width: CGFloat?, subviews: Subviews) -> InlineFlowLayoutResult {
        let maxWidth = max(width ?? 1, 1)
        // Every token is measured against the full line: a token that has to
        // wrap is laid out at the left margin anyway, and measuring against the
        // remaining width made wrapped text re-flow at two different widths.
        let tokens = subviews.map { subview -> InlineFlowToken in
            let dimensions = subview.dimensions(in: ProposedViewSize(width: maxWidth, height: nil))
            return InlineFlowToken(
                size: CGSize(width: dimensions.width, height: dimensions.height),
                baseline: dimensions[.firstTextBaseline]
            )
        }

        return InlineFlowLayoutEngine.layout(
            tokens: tokens,
            maxWidth: maxWidth,
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing
        )
    }
}
