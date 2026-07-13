import Foundation
import PDFKit
import CryptoKit

struct HoverProbeResult: Sendable {
    let snippet: String
    let cursorOffset: Int
}

enum PDFTextExtractor {
    nonisolated static func extractText(from page: PDFPage, bounds: NormalizedRect) -> String {
        let pageBounds = CoordinateMapper.pageBounds(for: page)
        let rect = bounds.cgRect(in: pageBounds)
        guard let selection = page.selection(for: rect) else { return "" }
        return selection.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// How close (in page points) the cursor must be to a page edge before the
    /// adjacent page's text is stitched into the hover snippet. Must exceed
    /// typical page margins, since the first/last text line sits a full margin
    /// away from the physical page edge (LaTeX book layouts run to ~100pt).
    private static let pageEdgeStitchThreshold: CGFloat = 140

    @MainActor
    static func extractHoverProbe(at viewPoint: CGPoint, in pdfView: PDFView, on page: PDFPage) -> HoverProbeResult? {
        extractHoverProbe(
            atPagePoint: pdfView.convert(viewPoint, to: page),
            on: page,
            in: pdfView.document
        )
    }

    @MainActor
    static func extractHoverProbe(atPagePoint pagePoint: CGPoint, on page: PDFPage, in document: PDFDocument?) -> HoverProbeResult? {
        // The probe must span the full line width: a reference like
        // "Definition 1.5.1" that wraps puts its two halves at opposite
        // horizontal ends of adjacent lines, so a box centered on the cursor
        // clips the other half out of the snippet.
        let pageBounds = CoordinateMapper.pageBounds(for: page)
        let probe = CGRect(
            x: pageBounds.minX,
            y: pagePoint.y - 30,
            width: pageBounds.width,
            height: 60
        )
        guard let selection = page.selection(for: probe),
              let rawSnippet = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawSnippet.isEmpty else {
            return nil
        }

        // The snippet is only used for reference detection; the cursor offset
        // is computed against the same dehyphenated text.
        var snippet = dehyphenate(rawSnippet)
        var cursorOffset = cursorOffsetInSnippet(
            snippet: snippet,
            probeSelection: selection,
            pagePoint: pagePoint,
            page: page
        )

        // A reference can also wrap across a page break, with its halves on
        // two different pages. When the cursor is near a page edge, stitch in
        // the adjacent page's edge strip (in reading order: the previous
        // page's bottom precedes the top of this page).
        if let document {
            let pageIndex = document.index(for: page)

            if pageBounds.maxY - pagePoint.y < pageEdgeStitchThreshold,
               pageIndex > 0,
               let previousPage = document.page(at: pageIndex - 1),
               let prefix = edgeStrip(of: previousPage, at: .bottom) {
                // Re-dehyphenate so a word split across the page break
                // ("Defi-" / "nition 1.5.1") is rejoined at the junction.
                snippet = dehyphenate(prefix + "\n" + snippet)
                cursorOffset += prefix.utf16.count + 1
            }

            if pagePoint.y - pageBounds.minY < pageEdgeStitchThreshold,
               pageIndex + 1 < document.pageCount,
               let nextPage = document.page(at: pageIndex + 1),
               let suffix = edgeStrip(of: nextPage, at: .top) {
                snippet = dehyphenate(snippet + "\n" + suffix)
            }
        }

        return HoverProbeResult(snippet: snippet, cursorOffset: min(cursorOffset, snippet.utf16.count))
    }

    private enum PageEdge {
        case top
        case bottom
    }

    private static func edgeStrip(of page: PDFPage, at edge: PageEdge) -> String? {
        let bounds = CoordinateMapper.pageBounds(for: page)
        let strip = CGRect(
            x: bounds.minX,
            y: edge == .bottom ? bounds.minY : bounds.maxY - pageEdgeStitchThreshold,
            width: bounds.width,
            height: pageEdgeStitchThreshold
        )
        guard let text = page.selection(for: strip)?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return dehyphenate(text)
    }

    /// Rejoins words hyphenated across a line break ("Defi-\nnition").
    private static func dehyphenate(_ text: String) -> String {
        text
            .replacingOccurrences(of: "-\n", with: "")
            .replacingOccurrences(of: "\u{2010}\n", with: "")
            .replacingOccurrences(of: "\u{00AD}\n", with: "")
    }

    @MainActor
    static func extractText(at viewPoint: CGPoint, in pdfView: PDFView, on page: PDFPage) -> String {
        extractHoverProbe(at: viewPoint, in: pdfView, on: page)?.snippet ?? ""
    }

    @MainActor
    private static func cursorOffsetInSnippet(
        snippet: String,
        probeSelection: PDFSelection,
        pagePoint: CGPoint,
        page: PDFPage
    ) -> Int {
        let pointRect = CGRect(x: pagePoint.x - 1, y: pagePoint.y - 1, width: 2, height: 2)
        guard let pointSelection = page.selection(for: pointRect),
              let pointText = pointSelection.string,
              !pointText.isEmpty else {
            return snippet.count / 2
        }

        if let range = snippet.range(of: pointText) {
            return range.lowerBound.utf16Offset(in: snippet)
        }

        let probeBounds = probeSelection.bounds(for: page)
        let pointBounds = pointSelection.bounds(for: page)
        if !probeBounds.isEmpty, !pointBounds.isEmpty {
            let relativeX = (pointBounds.midX - probeBounds.minX) / max(probeBounds.width, 1)
            let clamped = max(0, min(1, relativeX))
            return Int(Double(snippet.count) * clamped)
        }

        return snippet.count / 2
    }

    @MainActor
    static func currentSelectionText(in pdfView: PDFView) -> String {
        pdfView.currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    @MainActor
    static func buildSelectionContext(from pdfView: PDFView) -> TextSelectionContext? {
        guard let selection = pdfView.currentSelection,
              let selectedText = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !selectedText.isEmpty,
              let document = pdfView.document,
              let page = selection.pages.first ?? pageForSelection(selection, in: pdfView) else {
            return nil
        }

        let pageIndex = document.index(for: page)
        let surroundingText = expandContext(selectedText: selectedText, on: page)
        let bounds = normalizedBounds(for: selection, page: page, pdfView: pdfView)
        let lineBounds = normalizedLineBounds(for: selection, page: page, pdfView: pdfView)
        let fingerprint = fingerprint(pageIndex: pageIndex, selectedText: selectedText)

        return TextSelectionContext(
            pageIndex: pageIndex,
            selectedText: selectedText,
            surroundingText: surroundingText,
            fingerprint: fingerprint,
            bounds: bounds,
            lineBounds: lineBounds
        )
    }

    @MainActor
    private static func pageForSelection(_ selection: PDFSelection, in pdfView: PDFView) -> PDFPage? {
        guard let document = pdfView.document else { return nil }
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let bounds = selection.bounds(for: page)
            if !bounds.isEmpty {
                return page
            }
        }
        return nil
    }

    @MainActor
    private static func normalizedLineBounds(
        for selection: PDFSelection,
        page: PDFPage,
        pdfView: PDFView
    ) -> [NormalizedRect]? {
        let lineSelections = selection.selectionsByLine()
        guard lineSelections.count > 1 else { return nil }

        let rects = lineSelections.compactMap { lineSelection -> NormalizedRect? in
            let lineBounds = lineSelection.bounds(for: page)
            guard !lineBounds.isEmpty else { return nil }
            let rectInPDFView = pdfView.convert(lineBounds, from: page)
            return CoordinateMapper.normalizedRect(from: rectInPDFView, in: pdfView, page: page)
        }

        return rects.isEmpty ? nil : rects
    }

    @MainActor
    private static func normalizedBounds(
        for selection: PDFSelection,
        page: PDFPage,
        pdfView: PDFView
    ) -> NormalizedRect? {
        let selectionBounds = selection.bounds(for: page)
        guard !selectionBounds.isEmpty else { return nil }
        let rectInPDFView = pdfView.convert(selectionBounds, from: page)
        return CoordinateMapper.normalizedRect(from: rectInPDFView, in: pdfView, page: page)
    }

    static func expandContext(selectedText: String, on page: PDFPage, padding: Int = 400) -> String {
        let pageBounds = page.bounds(for: .mediaBox)
        guard let fullSelection = page.selection(for: pageBounds),
              let fullText = fullSelection.string,
              !fullText.isEmpty else {
            return selectedText
        }

        guard let range = fullText.range(of: selectedText) else {
            return selectedText
        }

        var start = range.lowerBound
        var end = range.upperBound

        let before = fullText[..<start]
        if let lastBreak = before.range(of: "\n\n", options: .backwards) {
            start = lastBreak.upperBound
        } else {
            start = fullText.index(start, offsetBy: -padding, limitedBy: fullText.startIndex) ?? fullText.startIndex
        }

        let after = fullText[end...]
        if let nextBreak = after.range(of: "\n\n") {
            end = nextBreak.lowerBound
        } else {
            end = fullText.index(end, offsetBy: padding, limitedBy: fullText.endIndex) ?? fullText.endIndex
        }

        return String(fullText[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func fingerprint(pageIndex: Int, selectedText: String) -> String {
        let input = "\(pageIndex)|\(selectedText)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
