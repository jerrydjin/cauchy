import AppKit
import PDFKit

@MainActor
protocol PDFViewportControllerDelegate: AnyObject {
    func viewportController(_ controller: PDFViewportController, didUpdate state: ViewportState)
}

@MainActor
final class PDFViewportController: NSObject {
    let role: ViewportRole
    weak var delegate: PDFViewportControllerDelegate?
    weak var pdfView: PDFView?

    var isApplyingProgrammaticChange = false

    private var pendingFitToWidth = false
    private var pendingViewChange: Task<Void, Never>?

    init(role: ViewportRole) {
        self.role = role
        super.init()
    }

    func attach(to pdfView: PDFView) {
        self.pdfView = pdfView
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleViewChanged),
            name: Notification.Name.PDFViewScaleChanged,
            object: pdfView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleViewChanged),
            name: Notification.Name.PDFViewPageChanged,
            object: pdfView
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleViewChanged() {
        guard !isApplyingProgrammaticChange else { return }
        pendingViewChange?.cancel()
        pendingViewChange = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            self?.publishCurrentState()
        }
    }

    func publishCurrentState() {
        guard !isApplyingProgrammaticChange, let pdfView, let document = pdfView.document else { return }
        let pageIndex: Int
        if let page = pdfView.currentPage {
            pageIndex = document.index(for: page)
        } else {
            pageIndex = 0
        }
        var state = ViewportState.default
        state.pageIndex = max(0, pageIndex)
        state.scaleFactor = pdfView.scaleFactor
        state.visibleRectNormalized = computeVisibleRect(in: pdfView)
        delegate?.viewportController(self, didUpdate: state)
    }

    func apply(state: ViewportState, animated: Bool) {
        guard let pdfView, let document = pdfView.document else { return }
        isApplyingProgrammaticChange = true

        if state.scaleFactor < 0 {
            applyFitToWidth(in: pdfView)
        } else if abs(pdfView.scaleFactor - state.scaleFactor) > 0.001 {
            pdfView.scaleFactor = state.scaleFactor
        }

        if let page = document.page(at: state.pageIndex) {
            if let normalized = state.visibleRectNormalized {
                let pageBounds = CoordinateMapper.pageBounds(for: page)
                let pageRect = normalized.cgRect(in: pageBounds)
                pdfView.go(to: pageRect, on: page)
            } else {
                pdfView.go(to: page)
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isApplyingProgrammaticChange = false
            self.publishCurrentState()
        }
    }

    func applyFitToWidthIfNeeded() {
        guard pendingFitToWidth, let pdfView, pdfView.bounds.width > 50 else { return }
        pendingFitToWidth = false
        isApplyingProgrammaticChange = true
        applyFitToWidth(in: pdfView)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isApplyingProgrammaticChange = false
            self.publishCurrentState()
        }
    }

    private func applyFitToWidth(in pdfView: PDFView) {
        let viewWidth = pdfView.bounds.width
        guard viewWidth > 50 else {
            pendingFitToWidth = true
            return
        }
        pendingFitToWidth = false
        pdfView.scaleFactor = fitToWidthScale(in: pdfView)
    }

    private func fitToWidthScale(in pdfView: PDFView) -> CGFloat {
        guard let page = pdfView.currentPage ?? pdfView.document?.page(at: 0) else {
            return 1.0
        }
        let pageWidth = page.bounds(for: .mediaBox).width
        let viewWidth = pdfView.bounds.width
        guard pageWidth > 0, viewWidth > 0 else { return 1.0 }
        return viewWidth / pageWidth
    }

    func navigate(to pageIndex: Int, highlight bounds: NormalizedRect?, scale: CGFloat?) {
        guard let pdfView, let document = pdfView.document,
              let page = document.page(at: pageIndex) else { return }

        isApplyingProgrammaticChange = true

        if let scale, abs(pdfView.scaleFactor - scale) > 0.001 {
            pdfView.scaleFactor = scale
        }

        if let bounds {
            let pageBounds = CoordinateMapper.pageBounds(for: page)
            let pageRect = bounds.cgRect(in: pageBounds)
            pdfView.go(to: pageRect, on: page)
        } else {
            pdfView.go(to: page)
        }

        DispatchQueue.main.async { [weak self] in
            self?.isApplyingProgrammaticChange = false
            self?.publishCurrentState()
        }
    }

    private func computeVisibleRect(in pdfView: PDFView) -> NormalizedRect? {
        guard let page = pdfView.currentPage,
              let documentView = pdfView.documentView else { return nil }

        let visibleInDocument = pdfView.convert(pdfView.bounds, to: documentView)
        let pageBounds = CoordinateMapper.pageBounds(for: page)
        let pageRectInDocument = pdfView.convert(pageBounds, from: page)
        let intersection = visibleInDocument.intersection(pageRectInDocument)
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { return nil }

        let pageRect = pdfView.convert(intersection, to: page)
        return NormalizedRect.from(cgRect: pageRect, pageBounds: pageBounds)
    }
}
