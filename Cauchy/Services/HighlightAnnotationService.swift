import AppKit
import PDFKit

@MainActor
enum HighlightAnnotationService {
    static let markerUserName = "Cauchy"
    private static let highlightIDKey = PDFAnnotationKey(rawValue: "/CauchyHighlightID")

    static func sync(document: PDFDocument, highlights: [Highlight], activeID: UUID?) {
        removeAllCauchyAnnotations(from: document)
        for highlight in highlights {
            addAnnotations(for: highlight, to: document, isActive: highlight.id == activeID)
        }
    }

    static func removeAllCauchyAnnotations(from document: PDFDocument) {
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let toRemove = page.annotations.filter { $0.userName == markerUserName }
            for annotation in toRemove {
                page.removeAnnotation(annotation)
            }
        }
    }

    static func highlightID(from annotation: PDFAnnotation) -> UUID? {
        guard annotation.userName == markerUserName,
              let idString = annotation.value(forAnnotationKey: highlightIDKey) as? String
        else { return nil }
        return UUID(uuidString: idString)
    }

    private static func addAnnotations(
        for highlight: Highlight,
        to document: PDFDocument,
        isActive: Bool
    ) {
        guard let page = document.page(at: highlight.pageIndex) else { return }
        let rects = annotationRects(for: highlight, on: page)
        guard !rects.isEmpty else { return }

        let color = isActive
            ? NSColor.systemYellow.withAlphaComponent(0.45)
            : NSColor.systemYellow.withAlphaComponent(0.30)

        for rect in rects {
            let annotation = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
            annotation.color = color
            annotation.userName = markerUserName
            // Stored under a custom key rather than `contents`, because PDFKit
            // renders any annotation with non-empty contents as a note icon + popup.
            annotation.setValue(highlight.id.uuidString as NSString, forAnnotationKey: highlightIDKey)
            page.addAnnotation(annotation)
        }
    }

    private static func annotationRects(for highlight: Highlight, on page: PDFPage) -> [CGRect] {
        let pageBounds = CoordinateMapper.pageBounds(for: page)

        if let lineBounds = highlight.lineBounds, !lineBounds.isEmpty {
            return lineBounds.map { $0.cgRect(in: pageBounds) }
        }

        if let bounds = highlight.bounds {
            let rect = bounds.cgRect(in: pageBounds)
            if let selection = page.selection(for: rect) {
                let selectionBounds = selection.bounds(for: page)
                if !selectionBounds.isEmpty {
                    return [selectionBounds]
                }
            }
            return [rect]
        }

        return []
    }
}
