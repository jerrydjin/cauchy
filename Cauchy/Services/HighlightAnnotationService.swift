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
        let color = isActive
            ? NSColor.systemYellow.withAlphaComponent(0.45)
            : NSColor.systemYellow.withAlphaComponent(0.30)

        for (pageIndex, rects) in annotationRects(for: highlight, in: document) {
            guard let page = document.page(at: pageIndex) else { continue }
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
    }

    /// The rects to paint, keyed by the page they belong to. An annotation only
    /// draws on the page it is added to, so a highlight dragged across a page
    /// break has to be split back out per page.
    private static func annotationRects(for highlight: Highlight, in document: PDFDocument) -> [Int: [CGRect]] {
        if let lines = highlight.lines, !lines.isEmpty {
            var rectsByPage: [Int: [CGRect]] = [:]
            for line in lines {
                guard let page = document.page(at: line.pageIndex) else { continue }
                let pageBounds = CoordinateMapper.pageBounds(for: page)
                rectsByPage[line.pageIndex, default: []].append(line.rect.cgRect(in: pageBounds))
            }
            return rectsByPage
        }

        guard let page = document.page(at: highlight.pageIndex),
              let bounds = highlight.bounds else { return [:] }

        let rect = bounds.cgRect(in: CoordinateMapper.pageBounds(for: page))
        if let selection = page.selection(for: rect) {
            let selectionBounds = selection.bounds(for: page)
            if !selectionBounds.isEmpty {
                return [highlight.pageIndex: [selectionBounds]]
            }
        }
        return [highlight.pageIndex: [rect]]
    }
}
