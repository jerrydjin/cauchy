import AppKit
import QuartzCore

final class SelectionOverlayLayer: CALayer {
    var onSelectionCompleted: ((CGRect) -> Void)?
    var onSelectionCancelled: (() -> Void)?

    var isActive: Bool = false {
        didSet { isHidden = !isActive }
    }

    private var dragStart: CGPoint?
    private var currentRect: CGRect = .zero

    override init() {
        super.init()
        isHidden = true
        backgroundColor = NSColor.clear.cgColor
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func handleMouseDown(at point: CGPoint) {
        guard isActive else { return }
        dragStart = point
        currentRect = CGRect(origin: point, size: .zero)
        setNeedsDisplay()
    }

    func handleMouseDragged(to point: CGPoint) {
        guard isActive, let start = dragStart else { return }
        currentRect = rect(from: start, to: point)
        setNeedsDisplay()
    }

    func handleMouseUp(at point: CGPoint) {
        guard isActive, let start = dragStart else { return }
        let rect = rect(from: start, to: point)
        dragStart = nil
        currentRect = .zero
        setNeedsDisplay()

        if rect.width > 4, rect.height > 4 {
            onSelectionCompleted?(rect)
        } else {
            onSelectionCancelled?()
        }
    }

    override func draw(in ctx: CGContext) {
        guard isActive, currentRect.width > 0, currentRect.height > 0 else { return }
        ctx.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(2)
        ctx.setFillColor(NSColor.systemBlue.withAlphaComponent(0.15).cgColor)
        ctx.addRect(currentRect)
        ctx.drawPath(using: .fillStroke)
    }

    private func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
}
