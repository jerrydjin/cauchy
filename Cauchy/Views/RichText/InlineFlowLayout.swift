import SwiftUI

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
    static func layout(
        segmentSizes: [CGSize],
        maxWidth: CGFloat,
        horizontalSpacing: CGFloat = 4,
        verticalSpacing: CGFloat = 4
    ) -> InlineFlowLayoutResult {
        let maxWidth = max(maxWidth, 1)
        var placements: [InlineFlowLayoutPlacement] = []
        var resultWidth: CGFloat = 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for size in segmentSizes {
            let remainingWidth = max(0, maxWidth - x)

            if x > 0, size.width > remainingWidth {
                y += rowHeight + verticalSpacing
                x = 0
                rowHeight = 0
                placements.append(InlineFlowLayoutPlacement(x: x, y: y, size: size))
                rowHeight = max(rowHeight, size.height)
                x += size.width + horizontalSpacing
                resultWidth = max(resultWidth, min(x - horizontalSpacing, maxWidth))
                continue
            }

            placements.append(InlineFlowLayoutPlacement(x: x, y: y, size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + horizontalSpacing
            resultWidth = max(resultWidth, min(x - horizontalSpacing, maxWidth))
        }

        return InlineFlowLayoutResult(
            size: CGSize(width: min(resultWidth, maxWidth), height: y + rowHeight),
            placements: placements
        )
    }
}

struct InlineFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 4
    var verticalSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(
            proposal: ProposedViewSize(width: bounds.width, height: proposal.height),
            subviews: subviews
        )

        for (index, placement) in result.placements.enumerated() {
            guard index < subviews.count else { break }
            subviews[index].place(
                at: CGPoint(x: bounds.minX + placement.x, y: bounds.minY + placement.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(placement.size)
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> InlineFlowLayoutResult {
        let maxWidth = max(proposal.width ?? 1, 1)
        var placements: [InlineFlowLayoutPlacement] = []
        var resultWidth: CGFloat = 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let remainingWidth = max(0, maxWidth - x)
            let measureWidth = x > 0 ? remainingWidth : maxWidth
            let size = subview.sizeThatFits(ProposedViewSize(width: measureWidth, height: nil))

            if x > 0, size.width > remainingWidth {
                y += rowHeight + verticalSpacing
                x = 0
                rowHeight = 0
                let fullLineSize = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
                placements.append(InlineFlowLayoutPlacement(x: x, y: y, size: fullLineSize))
                rowHeight = max(rowHeight, fullLineSize.height)
                x += fullLineSize.width + horizontalSpacing
                resultWidth = max(resultWidth, min(x - horizontalSpacing, maxWidth))
                continue
            }

            placements.append(InlineFlowLayoutPlacement(x: x, y: y, size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + horizontalSpacing
            resultWidth = max(resultWidth, min(x - horizontalSpacing, maxWidth))
        }

        return InlineFlowLayoutResult(
            size: CGSize(width: min(resultWidth, maxWidth), height: y + rowHeight),
            placements: placements
        )
    }
}
