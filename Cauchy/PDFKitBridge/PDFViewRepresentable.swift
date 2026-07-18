import AppKit
import PDFKit
import SwiftUI

struct PDFViewportView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var viewportState: ViewportState
    let role: ViewportRole
    var selectionModeActive: Bool
    var pageLayoutMode: PDFPageLayoutMode
    var onSelectionCompleted: (SelectionCapture) -> Void
    var onViewportChanged: (ViewportState) -> Void
    var onTextSelectionChanged: (TextSelectionContext?) -> Void
    var onBlockDetected: (DocumentBlock?) -> Void
    var onHighlightSelected: (UUID) -> Void
    var referenceIndex: DocumentReferenceIndex?
    var referenceIndexReady = false
    var applyTrigger: UUID?
    var findMatches: [PDFSelection] = []
    var activeFindMatch: PDFSelection?
    var findRevision: UUID?
    var viewCommand: PDFViewCommand?
    var viewCommandRevision: UUID?
    var invertPageColors = false

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> PDFCanvasView {
        let canvas = PDFCanvasView(role: role)
        canvas.pdfView.document = document
        canvas.canvasDelegate = context.coordinator
        canvas.selectionModeActive = selectionModeActive
        canvas.pageLayoutMode = pageLayoutMode
        canvas.referenceIndex = referenceIndex
        canvas.referenceIndexReady = referenceIndexReady
        canvas.invertPageColors = invertPageColors
        context.coordinator.canvasView = canvas
        // A command that fired before this view existed is stale; don't replay it.
        context.coordinator.lastViewCommandRevision = viewCommandRevision
        return canvas
    }

    func updateNSView(_ canvas: PDFCanvasView, context: Context) {
        context.coordinator.parent = self

        if canvas.pdfView.document !== document {
            canvas.pdfView.document = document
        }

        canvas.selectionModeActive = selectionModeActive
        canvas.pageLayoutMode = pageLayoutMode
        canvas.referenceIndex = referenceIndex
        canvas.referenceIndexReady = referenceIndexReady
        canvas.invertPageColors = invertPageColors

        if context.coordinator.lastViewCommandRevision != viewCommandRevision {
            context.coordinator.lastViewCommandRevision = viewCommandRevision
            if let viewCommand, viewCommandRevision != nil {
                canvas.perform(viewCommand)
            }
        }

        if context.coordinator.lastApplyTrigger != applyTrigger {
            context.coordinator.lastApplyTrigger = applyTrigger
            canvas.viewportController.apply(state: viewportState, animated: false)
        }

        if context.coordinator.lastFindRevision != findRevision {
            context.coordinator.lastFindRevision = findRevision
            canvas.pdfView.highlightedSelections = findMatches.isEmpty ? nil : findMatches
            if let match = activeFindMatch {
                canvas.pdfView.go(to: match)
            }
        }
    }

    final class Coordinator: NSObject, PDFCanvasViewDelegate {
        var parent: PDFViewportView
        weak var canvasView: PDFCanvasView?
        var lastApplyTrigger: UUID?
        var lastFindRevision: UUID?
        var lastViewCommandRevision: UUID?

        init(parent: PDFViewportView) {
            self.parent = parent
        }

        @MainActor
        func canvasView(_ canvasView: PDFCanvasView, didCompleteSelection rect: CGRect) {
            let pdfView = canvasView.pdfView
            guard let document = pdfView.document else { return }

            let rectInPDFView = canvasView.convert(rect, to: pdfView)
            let center = CGPoint(x: rectInPDFView.midX, y: rectInPDFView.midY)
            guard let page = pdfView.page(for: center, nearest: true) else { return }

            let pageIndex = document.index(for: page)
            guard let normalized = CoordinateMapper.normalizedRect(
                from: rectInPDFView,
                in: pdfView,
                page: page
            ) else { return }

            let capture = SelectionCapture(
                pageIndex: pageIndex,
                bounds: normalized,
                viewRect: rect
            )
            parent.onSelectionCompleted(capture)
        }

        @MainActor
        func canvasViewDidCancelSelection(_ canvasView: PDFCanvasView) {}

        @MainActor
        func canvasView(_ canvasView: PDFCanvasView, didUpdateViewport state: ViewportState) {
            guard !canvasView.viewportController.isApplyingProgrammaticChange else { return }
            parent.onViewportChanged(state)
        }

        @MainActor
        func canvasView(_ canvasView: PDFCanvasView, didChangeTextSelection context: TextSelectionContext?) {
            parent.onTextSelectionChanged(context)
        }

        @MainActor
        func canvasView(_ canvasView: PDFCanvasView, didDetectBlock block: DocumentBlock?) {
            parent.onBlockDetected(block)
        }

        @MainActor
        func canvasView(_ canvasView: PDFCanvasView, didSelectHighlight id: UUID) {
            parent.onHighlightSelected(id)
        }
    }
}
