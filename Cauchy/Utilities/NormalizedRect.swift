import CoreGraphics

struct NormalizedRect: Codable, Equatable, Sendable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    func cgRect(in pageBounds: CGRect) -> CGRect {
        CGRect(
            x: pageBounds.origin.x + x * pageBounds.width,
            y: pageBounds.origin.y + y * pageBounds.height,
            width: width * pageBounds.width,
            height: height * pageBounds.height
        )
    }

    /// True when the two rects share any area, with a hair of slack so a
    /// passage that was just scrolled into view is not treated as gone.
    func intersects(_ other: NormalizedRect) -> Bool {
        let slop: CGFloat = 0.002
        return x < other.x + other.width + slop
            && other.x < x + width + slop
            && y < other.y + other.height + slop
            && other.y < y + height + slop
    }

    static func from(cgRect: CGRect, pageBounds: CGRect) -> NormalizedRect {
        guard pageBounds.width > 0, pageBounds.height > 0 else {
            return NormalizedRect(x: 0, y: 0, width: 0, height: 0)
        }
        return NormalizedRect(
            x: (cgRect.origin.x - pageBounds.origin.x) / pageBounds.width,
            y: (cgRect.origin.y - pageBounds.origin.y) / pageBounds.height,
            width: cgRect.width / pageBounds.width,
            height: cgRect.height / pageBounds.height
        )
    }
}
