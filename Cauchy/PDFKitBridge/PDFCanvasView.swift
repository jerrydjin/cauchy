import AppKit
import PDFKit
import QuartzCore

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

    private var hoverDebouncer = Debouncer(delay: 0.15)
    private var lastHoveredReference: DetectedReference?
    private var isOverReference = false

    var referenceIndex: DocumentReferenceIndex?
    var referenceIndexReady = false

    private func setup() {
        wantsLayer = true
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        applyPageLayoutMode()
        pdfView.displaysPageBreaks = true
        pdfView.autoScales = false
        pdfView.scaleFactor = 1.0
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
        let pointInPDF = convert(point, to: pdfView)

        hoverDebouncer.schedule { [weak self] in
            MainActor.assumeIsolated {
                self?.detectReference(at: pointInPDF)
            }
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

        guard let probe = PDFTextExtractor.extractHoverProbe(at: pointInPDF, in: pdfView, on: page),
              let reference = ReferenceDetector.bestReference(in: probe.snippet, cursorOffset: probe.cursorOffset),
              let indexed = referenceIndex?.lookup(reference),
              !indexed.formattedBody.isEmpty else {
            clearReferenceHoverState()
            return
        }

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
        if isOverReference {
            isOverReference = false
            NSCursor.pop()
        }
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
