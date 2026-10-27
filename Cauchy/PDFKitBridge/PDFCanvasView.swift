import AppKit
import CoreImage
import PDFKit
import QuartzCore
import SwiftUI

@MainActor
protocol PDFCanvasViewDelegate: AnyObject {
    func canvasView(_ canvasView: PDFCanvasView, didCompleteSelection rect: CGRect)
    func canvasViewDidCancelSelection(_ canvasView: PDFCanvasView)
    func canvasView(_ canvasView: PDFCanvasView, didUpdateViewport state: ViewportState)
    func canvasView(_ canvasView: PDFCanvasView, didChangeTextSelection context: TextSelectionContext?)
    func canvasView(_ canvasView: PDFCanvasView, didDetectBlock block: DocumentBlock?)
    func canvasView(_ canvasView: PDFCanvasView, didSelectHighlight id: UUID)
}

@MainActor
final class PDFCanvasView: NSView {
    let pdfView: PDFView
    let overlay: SelectionOverlayLayer
    let viewportController: PDFViewportController

    weak var canvasDelegate: PDFCanvasViewDelegate?

    var selectionModeActive: Bool = false {
        didSet {
            overlay.isActive = selectionModeActive
        }
    }

    var pageLayoutMode: PDFPageLayoutMode = .continuousScroll {
        didSet {
            guard pageLayoutMode != oldValue else { return }
            applyPageLayoutMode()
        }
    }

    /// Night-reading mode: inverts luminance, then rotates hue by π so figures
    /// keep roughly their original hues. Applied as layer content filters so
    /// the selection overlay (a sibling layer) stays untouched.
    var invertPageColors: Bool = false {
        didSet {
            guard invertPageColors != oldValue else { return }
            applyInvertPageColors()
        }
    }

    private func applyInvertPageColors() {
        if invertPageColors {
            var filters: [CIFilter] = []
            if let invert = CIFilter(name: "CIColorInvert") {
                filters.append(invert)
            }
            if let hue = CIFilter(name: "CIHueAdjust") {
                hue.setValue(Double.pi, forKey: kCIInputAngleKey)
                filters.append(hue)
            }
            // Force a white page background so inversion yields black, even
            // when the system appearance already darkened textBackgroundColor.
            pdfView.backgroundColor = .white
            pdfView.contentFilters = filters
        } else {
            pdfView.contentFilters = []
            pdfView.backgroundColor = .textBackgroundColor
        }
    }

    func perform(_ command: PDFViewCommand) {
        switch command {
        case .goBack:
            if pdfView.canGoBack { pdfView.goBack(nil) }
        case .goForward:
            if pdfView.canGoForward { pdfView.goForward(nil) }
        case .print:
            pdfView.print(with: .shared, autoRotate: true, pageScaling: .pageScaleDownToFit)
        }
    }

    init(role: ViewportRole) {
        pdfView = PDFView()
        overlay = SelectionOverlayLayer()
        viewportController = PDFViewportController(role: role)
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var pendingHoverDetection: Task<Void, Never>?
    private var lastHoveredReference: DetectedReference?
    private var isOverReference = false
    private weak var bibliographyDocument: PDFDocument?
    private var bibliographyEntries: [BibliographyEntry] = []
    /// View coordinates of the pointer. A system tooltip is plain text, so a
    /// bibliography line that contains math is shown in a popover instead.
    private var lastLocalHoverPoint = CGPoint.zero
    private var citationPopover: NSPopover?
    private var citationPopoverText: String?

    var referenceIndex: DocumentReferenceIndex?
    var referenceIndexReady = false

    private func setup() {
        wantsLayer = true
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        applyPageLayoutMode()
        pdfView.displaysPageBreaks = true
        pdfView.autoScales = false
        pdfView.scaleFactor = 1.0
        pdfView.minScaleFactor = 0.1
        pdfView.maxScaleFactor = 10.0
        pdfView.backgroundColor = .textBackgroundColor

        addSubview(pdfView)
        NSLayoutConstraint.activate([
            pdfView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        overlay.onSelectionCompleted = { [weak self] rect in
            guard let self else { return }
            self.canvasDelegate?.canvasView(self, didCompleteSelection: rect)
        }
        overlay.onSelectionCancelled = { [weak self] in
            guard let self else { return }
            self.canvasDelegate?.canvasViewDidCancelSelection(self)
        }

        layer?.addSublayer(overlay)

        viewportController.attach(to: pdfView)
        viewportController.delegate = self

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSelectionChanged),
            name: Notification.Name.PDFViewSelectionChanged,
            object: pdfView
        )

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleSelectionChanged() {
        guard !selectionModeActive else { return }
        let context = PDFTextExtractor.buildSelectionContext(from: pdfView)
        canvasDelegate?.canvasView(self, didChangeTextSelection: context)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard !selectionModeActive else { return }

        let point = convert(event.locationInWindow, from: nil)
        lastLocalHoverPoint = point
        let pointInPDF = convert(point, to: pdfView)

        pendingHoverDetection?.cancel()
        pendingHoverDetection = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.detectReference(at: pointInPDF)
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        clearReferenceHoverState()
    }

    private func detectReference(at pointInPDF: CGPoint) {
        guard referenceIndexReady,
              let page = pdfView.page(for: pointInPDF, nearest: true) else {
            clearReferenceHoverState()
            return
        }

        guard let probe = PDFTextExtractor.extractHoverProbe(at: pointInPDF, in: pdfView, on: page) else {
            clearReferenceHoverState()
            return
        }

        if let citation = ReferenceDetector.externalCitation(in: probe.snippet, cursorOffset: probe.cursorOffset) {
            // The result named in the citation belongs to the other paper.
            // Show its bibliography entry, or nothing when that entry is missing.
            // Clicking still does nothing: opening the cited paper is later.
            if let hover = BibliographyIndex.hoverText(for: citation, in: bibliography()) {
                lastHoveredReference = nil
                showCitationHover(hover)
                showReferenceCursor()
            } else {
                clearReferenceHoverState()
            }
            return
        }

        guard let reference = ReferenceDetector.bestReference(in: probe.snippet, cursorOffset: probe.cursorOffset),
              let indexed = referenceIndex?.lookup(reference),
              !indexed.formattedBody.isEmpty else {
            clearReferenceHoverState()
            return
        }
        toolTip = nil
        dismissCitationPopover()

        let block = DocumentBlockExtractor.block(from: indexed)

        guard reference != lastHoveredReference else {
            showReferenceCursor()
            return
        }

        lastHoveredReference = reference
        showReferenceCursor()
        canvasDelegate?.canvasView(self, didDetectBlock: block)
    }

    private func clearReferenceHoverState() {
        lastHoveredReference = nil
        toolTip = nil
        dismissCitationPopover()
        if isOverReference {
            isOverReference = false
            NSCursor.pop()
        }
    }

    /// Plain bibliography stays on the tooltip. Math in a title (`$K$-theory`,
    /// `\emph`) goes through `ReferenceHoverLabel`, the same renderer as the
    /// reference card. The tooltip cannot typeset.
    private func showCitationHover(_ text: String) {
        guard ReferenceMathRendering.needsTypesetting(text) else {
            dismissCitationPopover()
            toolTip = text
            return
        }
        toolTip = nil
        if citationPopoverText == text, citationPopover?.isShown == true {
            return
        }
        let popover = citationPopover ?? NSPopover()
        popover.behavior = .transient
        popover.animates = false
        if citationPopoverText != text {
            popover.contentViewController = NSHostingController(
                rootView: ReferenceHoverLabel(text: text)
            )
            citationPopoverText = text
        }
        citationPopover = popover
        let rect = CGRect(origin: lastLocalHoverPoint, size: CGSize(width: 1, height: 1))
        if popover.isShown {
            return
        }
        popover.show(relativeTo: rect, of: self, preferredEdge: .minY)
    }

    private func dismissCitationPopover() {
        citationPopover?.performClose(nil)
        citationPopoverText = nil
    }

    private func bibliography() -> [BibliographyEntry] {
        guard let document = pdfView.document else {
            bibliographyDocument = nil
            bibliographyEntries = []
            return []
        }
        if bibliographyDocument !== document {
            bibliographyDocument = document
            var pages: [String] = []
            pages.reserveCapacity(document.pageCount)
            for index in 0..<document.pageCount {
                if let text = document.page(at: index)?.string, !text.isEmpty {
                    pages.append(text)
                }
            }
            bibliographyEntries = BibliographyIndex.entries(in: pages.joined(separator: "\n"))
        }
        return bibliographyEntries
    }

    private func showReferenceCursor() {
        guard !isOverReference else { return }
        isOverReference = true
        NSCursor.pointingHand.push()
    }

    override func layout() {
        super.layout()
        overlay.frame = bounds
        viewportController.applyFitToWidthIfNeeded()
    }

    private func applyPageLayoutMode() {
        switch pageLayoutMode {
        case .continuousScroll:
            pdfView.displayMode = .singlePageContinuous
        case .singlePage:
            pdfView.displayMode = .singlePage
        case .twoPages:
            pdfView.displayMode = .twoUpContinuous
        }
        pdfView.displayDirection = .vertical
    }

    override func mouseDown(with event: NSEvent) {
        if selectionModeActive {
            let point = convert(event.locationInWindow, from: nil)
            overlay.handleMouseDown(at: point)
            return
        }

        if let highlightID = highlightID(at: event) {
            canvasDelegate?.canvasView(self, didSelectHighlight: highlightID)
            return
        }

        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if selectionModeActive {
            let point = convert(event.locationInWindow, from: nil)
            overlay.handleMouseDragged(to: point)
            return
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if selectionModeActive {
            let point = convert(event.locationInWindow, from: nil)
            overlay.handleMouseUp(at: point)
            return
        }
        super.mouseUp(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        viewportController.publishCurrentState()
    }

    private func highlightID(at event: NSEvent) -> UUID? {
        let point = convert(event.locationInWindow, from: nil)
        let pointInPDF = convert(point, to: pdfView)
        guard let page = pdfView.page(for: pointInPDF, nearest: true) else { return nil }
        let pagePoint = pdfView.convert(pointInPDF, to: page)

        for annotation in page.annotations.reversed() {
            guard annotation.type == "Highlight",
                  annotation.bounds.contains(pagePoint),
                  let id = HighlightAnnotationService.highlightID(from: annotation) else { continue }
            return id
        }
        return nil
    }
}

extension PDFCanvasView: PDFViewportControllerDelegate {
    func viewportController(_ controller: PDFViewportController, didUpdate state: ViewportState) {
        canvasDelegate?.canvasView(self, didUpdateViewport: state)
    }
}
