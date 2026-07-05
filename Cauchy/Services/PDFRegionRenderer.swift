import AppKit
import PDFKit

enum PDFRegionRenderer {
    static func render(page: PDFPage, bounds: NormalizedRect, scale: CGFloat = 2.0) -> CGImage? {
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
