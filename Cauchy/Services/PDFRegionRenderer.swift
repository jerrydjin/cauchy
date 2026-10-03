import AppKit
import PDFKit

enum PDFRegionRenderer {
    static func render(
        page: PDFPage,
        bounds: NormalizedRect,
        scale: CGFloat = 2.0,
        highlight: CGRect? = nil
    ) -> CGImage? {
        let pageBounds = CoordinateMapper.pageBounds(for: page)
        let cropRect = bounds.cgRect(in: pageBounds)

        let width = Int(cropRect.width * scale)
        let height = Int(cropRect.height * scale)
        guard width > 0, height > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -cropRect.origin.x, y: -cropRect.origin.y)
        page.draw(with: .mediaBox, to: context)
        if let highlight {
            context.setStrokeColor(NSColor.systemOrange.cgColor)
            context.setLineWidth(2 / scale)
            context.stroke(highlight.insetBy(dx: -2, dy: -2))
        }
        context.restoreGState()

        return context.makeImage()
    }

    static func renderFullPage(_ page: PDFPage, scale: CGFloat = 2.0, maxDimension: CGFloat = 2048) -> CGImage? {
        let pageBounds = page.bounds(for: .mediaBox)
        guard pageBounds.width > 0, pageBounds.height > 0 else { return nil }

        var effectiveScale = scale
        let scaledWidth = pageBounds.width * effectiveScale
        let scaledHeight = pageBounds.height * effectiveScale
        let longestEdge = max(scaledWidth, scaledHeight)
        if longestEdge > maxDimension {
            effectiveScale *= maxDimension / longestEdge
        }

        let width = Int(pageBounds.width * effectiveScale)
        let height = Int(pageBounds.height * effectiveScale)
        guard width > 0, height > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: effectiveScale, y: effectiveScale)
        page.draw(with: .mediaBox, to: context)

        return context.makeImage()
    }

    static func pngData(from image: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }

    static func saveThumbnail(_ image: CGImage, to url: URL) throws {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try data.write(to: url, options: .atomic)
    }

    static func renderPageThumbnail(page: PDFPage, maxWidth: CGFloat) -> NSImage? {
        let pageBounds = page.bounds(for: .mediaBox)
        guard pageBounds.width > 0, pageBounds.height > 0, maxWidth > 0 else { return nil }

        let scale = maxWidth / pageBounds.width
        let width = Int(pageBounds.width * scale)
        let height = Int(pageBounds.height * scale)
        guard width > 0, height > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)

        guard let cgImage = context.makeImage() else { return nil }
        let size = NSSize(width: pageBounds.width, height: pageBounds.height)
        return NSImage(cgImage: cgImage, size: size)
    }
}

enum ReferenceEvidenceRegionResolver {
    /// Resolve the exact printed heading/label. A mismatched text layer or
    /// out-of-range offset abstains rather than highlighting the wrong place.
    static func exactRegion(for evidence: ReferenceEvidence, on page: PDFPage) -> NormalizedRect? {
        if evidence.effectiveSource == .visionOCR {
            guard let region = evidence.matchedRegion,
                  region.x.isFinite, region.y.isFinite,
                  region.width.isFinite, region.height.isFinite,
                  region.x >= 0, region.y >= 0,
                  region.width > 0, region.height > 0,
                  region.x + region.width <= 1,
                  region.y + region.height <= 1 else { return nil }
            return region
        }
        guard let start = evidence.matchStartOffset,
              let end = evidence.matchEndOffset else { return nil }
        return exactRegion(
            matchedText: evidence.matchedText,
            startOffset: start,
            endOffset: end,
            on: page
        )
    }

    /// Shared strict resolver for declaration anchors and later citation
    /// edges. Never reuse text offsets against a differently extracted page.
    static func exactRegion(
        matchedText: String,
        startOffset start: Int,
        endOffset end: Int,
        on page: PDFPage
    ) -> NormalizedRect? {
        guard
              start >= 0, end > start,
              end <= page.numberOfCharacters,
              let text = page.string else { return nil }

        let range = NSRange(location: start, length: end - start)
        let source = text as NSString
        guard NSMaxRange(range) <= source.length,
              source.substring(with: range) == matchedText,
              let selection = page.selection(for: range) else { return nil }

        let rect = selection.bounds(for: page)
        let pageBounds = page.bounds(for: .mediaBox)
        guard !rect.isEmpty, pageBounds.contains(rect) else { return nil }
        return NormalizedRect.from(cgRect: rect, pageBounds: pageBounds)
    }

    /// Give the exact label enough surrounding page to inspect the statement
    /// and printed notation without losing the visual anchor.
    static func contextRegion(for exact: NormalizedRect) -> NormalizedRect {
        let height = min(1, max(0.18, exact.height * 8))
        let center = exact.y + exact.height / 2
        let y = max(0, min(1 - height, center - height / 2))
        return NormalizedRect(x: 0, y: y, width: 1, height: height)
    }
}
