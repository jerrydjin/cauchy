import PDFKit

enum CoordinateMapper {
    nonisolated static func pageBounds(for page: PDFPage) -> CGRect {
        page.bounds(for: .mediaBox)
    }

    @MainActor
    static func normalizedRect(from viewRect: CGRect, in pdfView: PDFView, page: PDFPage) -> NormalizedRect? {
        let pageRect = pdfView.convert(viewRect, to: page)
        let bounds = pageBounds(for: page)
        guard pageRect.width > 0, pageRect.height > 0 else { return nil }
        return NormalizedRect.from(cgRect: pageRect, pageBounds: bounds)
    }

    @MainActor
    static func viewRect(from normalized: NormalizedRect, in pdfView: PDFView, page: PDFPage) -> CGRect {
        let pageRect = normalized.cgRect(in: pageBounds(for: page))
        return pdfView.convert(pageRect, from: page)
    }
}
