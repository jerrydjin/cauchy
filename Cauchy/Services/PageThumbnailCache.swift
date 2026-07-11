import AppKit

/// Bounded in-memory cache for sidebar page thumbnails, so scrolling back to
/// an already-rendered page doesn't redraw it. Owned by WorkspaceViewModel and
/// cleared whenever the document changes, so entries can never be served for a
/// different document. NSCache additionally evicts under memory pressure.
@MainActor
final class PageThumbnailCache {
    private let cache = NSCache<NSString, NSImage>()

    init(countLimit: Int = 400) {
        cache.countLimit = countLimit
    }

    func image(pageIndex: Int, width: CGFloat) -> NSImage? {
        cache.object(forKey: key(pageIndex, width))
    }

    func store(_ image: NSImage, pageIndex: Int, width: CGFloat) {
        cache.setObject(image, forKey: key(pageIndex, width))
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    private func key(_ pageIndex: Int, _ width: CGFloat) -> NSString {
        "\(pageIndex)-\(Int(width))" as NSString
    }
}
