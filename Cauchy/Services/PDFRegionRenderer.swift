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
        // The bitmap's origin is the bottom left, and `PDFPage.draw` paints
        // PDF space the same way: y grows up. Map the crop's bottom-left onto
        // that origin. A y-flip here turns the page over, so the last line
        // lands on top.
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -cropRect.minX, y: -cropRect.minY)
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

    /// The statement body, not the heading. The card already prints the title,
    /// so the crop starts just below the heading's line box. A small pad keeps
    /// the edge off the glyphs. When the heading can't be found, both edges
    /// snap out to whole line boxes so a line is never cut in half. The same
    /// rule closes the bottom edge.
    static func statementBand(for evidence: ReferenceEvidence, on page: PDFPage) -> NormalizedRect? {
        let pageBounds = CoordinateMapper.pageBounds(for: page)
        let lines = textLineBoxes(on: page)
        let heading = headingLine(for: evidence, on: page, lines: lines)
        let proposed: CGRect
        if evidence.startOffset >= 0,
           evidence.endOffset > evidence.startOffset,
           let excerpt = exactRegion(
               matchedText: evidence.sourceExcerpt,
               startOffset: evidence.startOffset,
               endOffset: evidence.endOffset,
               on: page
           ) {
            proposed = excerpt.cgRect(in: pageBounds)
        } else if let label = exactRegion(for: evidence, on: page) {
            proposed = contextRegion(for: label).cgRect(in: pageBounds)
        } else if let heading {
            proposed = heading
        } else {
            return nil
        }
        let crop: CGRect
        if lines.isEmpty {
            crop = paddedBand(NormalizedRect.from(cgRect: proposed, pageBounds: pageBounds)).cgRect(in: pageBounds)
        } else {
            crop = statementCrop(proposed: proposed, lines: lines, headingLine: heading, pageBounds: pageBounds)
        }
        guard crop.width > 1, crop.height > 1 else { return nil }
        return NormalizedRect.from(cgRect: crop, pageBounds: pageBounds)
    }

    /// One box per visual line in the page's text layer.
    static func textLineBoxes(on page: PDFPage) -> [CGRect] {
        guard let text = page.string, !text.isEmpty else { return [] }
        let range = NSRange(location: 0, length: (text as NSString).length)
        guard let selection = page.selection(for: range) else { return [] }
        return selection.selectionsByLine().compactMap { line in
            let bounds = line.bounds(for: page)
            guard !bounds.isNull, !bounds.isEmpty, bounds.width > 0.5, bounds.height > 0.5 else { return nil }
            return bounds
        }
    }

    /// `headingLine` is the heading's line box when the text layer has one.
    /// The crop then begins just under that box. Otherwise every line the
    /// proposal meets is taken whole, including at the bottom edge.
    static func statementCrop(
        proposed: CGRect,
        lines: [CGRect],
        headingLine heading: CGRect?,
        pageBounds: CGRect
    ) -> CGRect {
        let belowHeading: (CGRect) -> Bool = { line in
            guard let heading else { return true }
            return line.midY < heading.minY - 0.5
        }
        var included = lines.filter { belowHeading($0) && $0.intersects(proposed) }
        if included.isEmpty, let heading {
            let band = CGRect(
                x: proposed.minX,
                y: heading.minY - max(proposed.height, 36),
                width: proposed.width,
                height: max(proposed.height, 36)
            )
            included = lines.filter { belowHeading($0) && $0.intersects(band) }
        }
        if included.isEmpty {
            included = lines.filter { $0.intersects(proposed) }
        }
        guard !included.isEmpty else { return proposed.intersection(pageBounds) }
        return enclose(included, lines: lines, headingLine: heading, pageBounds: pageBounds)
    }

    /// Gap between the heading's line box and the crop, and around the body.
    private static let linePad: CGFloat = 3

    private static func enclose(
        _ included: [CGRect],
        lines: [CGRect],
        headingLine heading: CGRect?,
        pageBounds: CGRect
    ) -> CGRect {
        let union = included.reduce(CGRect.null) { $0.union($1) }
        guard !union.isNull else { return .null }
        var minX = union.minX - linePad
        var maxX = union.maxX + linePad
        var minY = union.minY - linePad
        var maxY = union.maxY + linePad
        if let heading, union.maxY <= heading.minY {
            let limit = heading.minY - min(linePad, max(0.5, heading.minY - union.maxY))
            maxY = min(maxY, max(limit, union.maxY))
        }
        let excluded = lines.filter { line in !included.contains { rectsMatch($0, line) } }
        for line in excluded {
            let crossesX = maxX > line.minX && minX < line.maxX
            let crossesY = maxY > line.minY && minY < line.maxY
            guard crossesX, crossesY else { continue }
            if line.midY >= union.maxY {
                maxY = min(maxY, line.minY - 0.5)
            } else if line.midY <= union.minY {
                minY = max(minY, line.maxY + 0.5)
            } else if line.midX <= union.minX {
                minX = max(minX, line.maxX + 0.5)
            } else {
                maxX = min(maxX, line.minX - 0.5)
            }
        }
        minX = min(minX, union.minX)
        maxX = max(maxX, union.maxX)
        minY = min(minY, union.minY)
        maxY = max(maxY, union.maxY)
        if let heading, union.maxY <= heading.minY - 0.25 {
            maxY = min(maxY, heading.minY - 0.25)
        }
        let rect = CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
            .intersection(pageBounds)
        guard !rect.isNull, !rect.isEmpty else { return union.intersection(pageBounds) }
        return rect
    }

    private static func headingLine(
        for evidence: ReferenceEvidence,
        on page: PDFPage,
        lines: [CGRect]
    ) -> CGRect? {
        guard let region = exactRegion(for: evidence, on: page) else { return nil }
        let rect = region.cgRect(in: CoordinateMapper.pageBounds(for: page))
        let overlapping = lines.filter { $0.intersects(rect.insetBy(dx: -1, dy: -1)) }
        return overlapping.min { $0.minY < $1.minY }
    }

    private static func rectsMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 0.5
            && abs(lhs.minY - rhs.minY) < 0.5
            && abs(lhs.width - rhs.width) < 0.5
            && abs(lhs.height - rhs.height) < 0.5
    }

    private static func paddedBand(_ rect: NormalizedRect) -> NormalizedRect {
        let padX: CGFloat = 0.03
        let padY: CGFloat = 0.015
        let x = max(0, rect.x - padX)
        let y = max(0, rect.y - padY)
        let width = min(1 - x, rect.width + padX * 2)
        let height = min(1 - y, max(rect.height + padY * 2, 0.08))
        return NormalizedRect(x: x, y: y, width: width, height: height)
    }

    /// Give the exact label enough surrounding page to inspect the statement
    /// and printed notation without losing the visual anchor.
    static func contextRegion(for exact: NormalizedRect) -> NormalizedRect {
        let height = min(1, max(0.18, exact.height * 8))
        let center = exact.y + exact.height / 2
        let y = max(0, min(1 - height, center - height / 2))
        return NormalizedRect(x: 0, y: y, width: 1, height: height)
    }

    /// A clear crop of the figure next to its printed caption label.
    /// PDF y grows upward, so the graphic is usually the band above the
    /// caption. A label parked at the top of the page is treated as a
    /// caption-above-figure and the crop drops below it instead. This is a
    /// page band, not a detected figure box.
    static func figureRegion(forCaption caption: NormalizedRect) -> NormalizedRect {
        let margin: CGFloat = 0.012
        let minimum: CGFloat = 0.16
        let preferred: CGFloat = 0.55

        let aboveBottom = min(1, max(0, caption.y + caption.height + margin))
        let roomAbove = 1 - aboveBottom
        if roomAbove >= minimum {
            return NormalizedRect(x: 0, y: aboveBottom, width: 1, height: min(preferred, roomAbove))
        }

        let belowTop = min(1, max(0, caption.y - margin))
        if belowTop >= minimum {
            let height = min(preferred, belowTop)
            return NormalizedRect(x: 0, y: belowTop - height, width: 1, height: height)
        }

        return NormalizedRect(x: 0, y: 0, width: 1, height: 1)
    }
}
