import AppKit
import Foundation
import FoundationModels
import Observation
import PDFKit
import UniformTypeIdentifiers

@MainActor
@Observable
final class WorkspaceViewModel {
    var workspace: DocumentWorkspace?
    var pdfDocument: PDFDocument?
    var bookmarkData: Data?

    var sidebarVisible = true
    var sidebarContentMode: SidebarContentMode = .thumbnails
    var pdfPageLayoutMode: PDFPageLayoutMode = .continuousScroll

    var selectionModeActive = false
    var showOCRResult = false
    var ocrResult: OCRResult?
    var ocrPreviewImage: CGImage?
    var isProcessingOCR = false
    var errorMessage: String?

    var viewportCoordinator = ViewportCoordinator()
    let pageThumbnailCache = PageThumbnailCache()
    var highlightStore = HighlightStore()
    var contextEngine = ContextEngineViewModel()
    var selectionThread = SelectionThreadViewModel()
    var referenceIndex = DocumentReferenceIndex()
    var find = PDFFindModel()
    var isIndexingReferences = false
    var referenceIndexProgress: Double = 0
    var referenceIndexError: String?
    /// Non-blocking notice for a partially failed index (hover still works
    /// with what was indexed; the failed pages retry next open).
    var referenceIndexWarning: String?

    private let persistence = DocumentPersistenceService.shared
    private var securityScopedURL: URL?
    private var referenceIndexTask: Task<Void, Never>?

    init() {
        find.currentPageProvider = { [weak self] in
            self?.viewportCoordinator.viewport.pageIndex ?? 0
        }
    }

    var documentTitle: String {
        workspace?.documentURL.deletingPathExtension().lastPathComponent ?? "No Document"
    }

    var windowTitle: String {
        pdfDocument != nil ? documentTitle : "Cauchy"
    }

    var pageCount: Int {
        pdfDocument?.pageCount ?? 0
    }

    var currentPage: Int {
        viewportCoordinator.viewport.pageIndex + 1
    }

    var readingAssistantAvailability: ReadingAssistantAvailability {
        ReadingAssistantProviderFactory.availability
    }

    func refreshReadingAssistant() {
        selectionThread.reloadAssistant(documentTitle: documentTitle)
    }

    var contextPanelWidth: CGFloat {
        get { workspace?.contextPanelWidth ?? 380 }
        set {
            workspace?.contextPanelWidth = min(640, max(300, newValue))
            persistWorkspace()
        }
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await openDocument(at: url) }
    }

    func openDocument(at url: URL) async {
        stopSecurityScopedAccess()
        pageThumbnailCache.removeAll()

        let persisted = try? await persistence.loadWorkspace(for: url)

        var resolvedURL = url
        if let bookmark = persisted?.bookmarkData,
           let bookmarkURL = try? persistence.resolveBookmark(bookmark) {
            resolvedURL = bookmarkURL
        } else {
            _ = url.startAccessingSecurityScopedResource()
        }
        securityScopedURL = resolvedURL

        guard let document = PDFDocument(url: resolvedURL) else {
            errorMessage = "Could not open PDF."
            stopSecurityScopedAccess()
            return
        }

        pdfDocument = document
        find.attach(to: document)
        bookmarkData = try? persistence.createBookmark(for: resolvedURL)

        let isNewDocument: Bool
        if let persisted {
            isNewDocument = false
            workspace = persisted.workspace
            workspace?.documentURL = resolvedURL
            workspace?.lastOpenedAt = Date()
            viewportCoordinator.viewport = persisted.workspace.primaryViewport
            highlightStore.load(from: persisted.workspace)
            if let bookmark = persisted.bookmarkData {
                bookmarkData = bookmark
            }
        } else {
            isNewDocument = true
            workspace = DocumentWorkspace(documentURL: resolvedURL)
            highlightStore.highlights = []
        }

        contextEngine.reset()
        selectionThread.activeThread = nil
        workspace?.lastOpenedAt = Date()
        applyRestoredViewport(isNewDocument: isNewDocument)
        syncHighlightAnnotations()
        buildReferenceIndex(for: resolvedURL)
        generateDashboardPreviewIfNeeded(documentURL: resolvedURL)
        persistWorkspace()
    }

    func closeDocument() {
        if workspace != nil {
            persistWorkspace()
        }

        stopSecurityScopedAccess()
        pdfDocument = nil
        workspace = nil
        bookmarkData = nil

        pageThumbnailCache.removeAll()
        highlightStore.highlights.removeAll()
        referenceIndex.clear()
        referenceIndexWarning = nil
        find.attach(to: nil)
        selectionThread.activeThread = nil
        contextEngine.reset()
        viewportCoordinator = ViewportCoordinator()
        
        selectionModeActive = false
        showOCRResult = false
        ocrResult = nil
        ocrPreviewImage = nil
        errorMessage = nil
        isProcessingOCR = false
    }

    func handleSelection(_ capture: SelectionCapture) {
        highlightStore.pendingRegionCapture = capture
        selectionModeActive = false
    }

    func handleTextSelection(_ context: TextSelectionContext?) {
        if let context, !context.selectedText.isEmpty {
            selectionThread.updateSelection(
                context,
                documentTitle: documentTitle,
                existingHighlights: highlightStore.highlights
            )
            if let match = highlightStore.findMatchingHighlight(for: context) {
                selectHighlight(match)
            } else {
                highlightStore.selectedHighlightID = nil
                contextEngine.showComposeDraft(context)
            }
        } else if case .list = contextEngine.route {
            selectionThread.updateSelection(
                nil,
                documentTitle: documentTitle,
                existingHighlights: highlightStore.highlights
            )
        }
    }

    func handleDetectedBlock(_ block: DocumentBlock?) {
        guard let block else { return }

        if contextEngine.passiveBlock?.reference.key == block.reference.key {
            return
        }

        contextEngine.showReferencePreview(block: block)
    }

    func navigateToReference(_ block: DocumentBlock) {
        viewportCoordinator.navigateToPage(block.pageIndex)
    }

    func showHighlightList() {
        contextEngine.showList()
        highlightStore.selectedHighlightID = nil
        syncHighlightAnnotations()
    }

    func deleteHighlight(_ highlight: Highlight) {
        highlightStore.remove(highlight)
        if case .detail(highlight.id) = contextEngine.route {
            contextEngine.showList()
        }
        if highlightStore.selectedHighlightID == highlight.id {
            highlightStore.selectedHighlightID = nil
        }
        syncHighlightAnnotations()
        persistWorkspace()
    }

    func saveTextSelectionAsHighlight() {
        guard var thread = selectionThread.activeThread else { return }
        thread.isPersisted = true
        selectionThread.activeThread = thread
        
        let highlight = highlightStore.upsertFromThread(thread)
        selectHighlight(highlight)
        persistWorkspace()
    }

    func saveRegionAsHighlight() async {
        guard let capture = highlightStore.pendingRegionCapture else { return }

        var selectedText = ""
        if let document = pdfDocument,
           let page = document.page(at: capture.pageIndex) {
            selectedText = PDFTextExtractor.extractText(from: page, bounds: capture.bounds)
            if selectedText.isEmpty,
               let image = PDFRegionRenderer.render(page: page, bounds: capture.bounds),
               let ocrText = try? await OCRService.shared.recognizeText(in: image).rawText {
                selectedText = ocrText
            }
        }

        if selectedText.isEmpty {
            selectedText = "Region on page \(capture.pageIndex + 1)"
        }

        let highlight = Highlight(
            pageIndex: capture.pageIndex,
            bounds: capture.bounds,
            selectedText: selectedText,
            surroundingText: selectedText,
            messages: selectionThread.currentMessagesForSave()
        )
        highlightStore.add(highlight)
        highlightStore.pendingRegionCapture = nil
        selectHighlight(highlight)
        persistWorkspace()
    }

    func selectHighlight(_ highlight: Highlight) {
        highlightStore.selectedHighlightID = highlight.id
        contextEngine.showDetail(highlight.id)
        selectionThread.restoreThread(from: highlight, documentTitle: documentTitle)
        navigateToHighlight(highlight)
        syncHighlightAnnotations()
    }

    func selectHighlight(id: UUID) {
        guard let highlight = highlightStore.highlights.first(where: { $0.id == id }) else { return }
        selectHighlight(highlight)
    }

    func navigateToHighlight(_ highlight: Highlight) {
        viewportCoordinator.navigateToHighlight(highlight)
    }

    func runOCR(on capture: SelectionCapture) async {
        guard let document = pdfDocument,
              let page = document.page(at: capture.pageIndex),
              let image = PDFRegionRenderer.render(page: page, bounds: capture.bounds) else {
            errorMessage = "Could not render selection for OCR."
            return
        }

        isProcessingOCR = true
        defer { isProcessingOCR = false }

        do {
            let result = try await OCRService.shared.recognizeText(in: image)
            ocrResult = result
            ocrPreviewImage = image
            showOCRResult = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func copyLatexToClipboard() {
        guard let latex = ocrResult?.latexSnippet else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(latex, forType: .string)
    }

    func sendThreadMessage(_ question: String) async {
        do {
            try await selectionThread.sendMessage(question, documentTitle: documentTitle) { [weak self] thread in
                guard let self else { return }
                let highlight = self.highlightStore.upsertFromThread(thread)
                self.highlightStore.selectedHighlightID = highlight.id
                self.contextEngine.showDetail(highlight.id)
                self.syncHighlightAnnotations()
                self.persistWorkspace()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func syncHighlightAnnotations() {
        guard let document = pdfDocument else { return }
        HighlightAnnotationService.sync(
            document: document,
            highlights: highlightStore.highlights,
            activeID: highlightStore.selectedHighlightID
        )
    }

    func zoomIn() { adjustZoom(by: 1.25) }
    func zoomOut() { adjustZoom(by: 0.8) }

    func zoomToActualSize() {
        var state = viewportCoordinator.viewport
        state.scaleFactor = 1.0
        viewportCoordinator.applyProgrammaticViewport(state)
    }

    func zoomToFitWidth() {
        var state = viewportCoordinator.viewport
        state.scaleFactor = -1
        viewportCoordinator.applyProgrammaticViewport(state)
    }

    func goToNextPage() {
        guard let document = pdfDocument else { return }
        var state = viewportCoordinator.viewport
        state.pageIndex = min(state.pageIndex + 1, document.pageCount - 1)
        state.visibleRectNormalized = nil
        viewportCoordinator.applyProgrammaticViewport(state)
    }

    func goToPreviousPage() {
        var state = viewportCoordinator.viewport
        state.pageIndex = max(state.pageIndex - 1, 0)
        state.visibleRectNormalized = nil
        viewportCoordinator.applyProgrammaticViewport(state)
    }

    func presentFindBar() {
        guard pdfDocument != nil else { return }
        find.present()
    }

    func presentGoToPagePanel() {
        guard let document = pdfDocument else { return }
        let alert = NSAlert()
        alert.messageText = "Go to Page"
        alert.informativeText = "Enter a page number (1–\(document.pageCount))"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.stringValue = "\(viewportCoordinator.viewport.pageIndex + 1)"
        alert.accessoryView = input
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn,
           let page = Int(input.stringValue.trimmingCharacters(in: .whitespaces)) {
            goToPage(page)
        }
    }

    func goToPage(_ page: Int) {
        guard let document = pdfDocument,
              page >= 1, page <= document.pageCount else { return }
        var state = viewportCoordinator.viewport
        state.pageIndex = page - 1
        state.visibleRectNormalized = nil
        viewportCoordinator.applyProgrammaticViewport(state)
    }

    func navigateToDestination(_ destination: PDFDestination) {
        guard let document = pdfDocument,
              let page = destination.page else { return }
        let pageIndex = document.index(for: page)
        var state = viewportCoordinator.viewport
        state.pageIndex = max(0, pageIndex)
        let point = destination.point
        let pageBounds = CoordinateMapper.pageBounds(for: page)
        state.visibleRectNormalized = NormalizedRect.from(
            cgRect: CGRect(origin: point, size: CGSize(width: 1, height: 1)),
            pageBounds: pageBounds
        )
        viewportCoordinator.applyProgrammaticViewport(state)
    }

    func persistWorkspace() {
        guard var ws = workspace else { return }
        ws.primaryViewport = viewportCoordinator.viewport
        highlightStore.exportToWorkspace(&ws)
        workspace = ws
        persistence.scheduleSave(ws, bookmarkData: bookmarkData) { [weak self] error in
            Task { @MainActor in
                self?.errorMessage = "Could not save workspace: \(error.localizedDescription)"
            }
        }
    }

    /// Renders the first page to thumbnails/preview.png once per workspace so
    /// the dashboard can show recents without reopening every PDF. Uses its own
    /// PDFDocument instance so background drawing never races the live PDFView.
    private func generateDashboardPreviewIfNeeded(documentURL: URL) {
        guard let workspaceID = workspace?.id else { return }
        let previewURL = persistence.thumbnailURL(workspaceID: workspaceID, filename: "preview.png")
        guard !FileManager.default.fileExists(atPath: previewURL.path) else { return }

        Task.detached(priority: .background) {
            guard let document = PDFDocument(url: documentURL),
                  let page = document.page(at: 0),
                  let image = PDFRegionRenderer.renderFullPage(page, maxDimension: 600)
            else { return }
            try? FileManager.default.createDirectory(
                at: previewURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? PDFRegionRenderer.saveThumbnail(image, to: previewURL)
        }
    }

    private func applyRestoredViewport(isNewDocument: Bool) {
        if isNewDocument || viewportCoordinator.viewport.scaleFactor < 0.15 {
            var fitState = viewportCoordinator.viewport
            fitState.scaleFactor = -1
            fitState.visibleRectNormalized = nil
            viewportCoordinator.applyProgrammaticViewport(fitState)
        } else {
            viewportCoordinator.applyProgrammaticViewport(viewportCoordinator.viewport)
        }
    }

    private func adjustZoom(by factor: CGFloat) {
        var state = viewportCoordinator.viewport
        let currentScale = state.scaleFactor > 0 ? state.scaleFactor : 1.0
        state.scaleFactor = max(0.1, min(10.0, currentScale * factor))
        viewportCoordinator.applyProgrammaticViewport(state)
    }

    private func buildReferenceIndex(for url: URL) {
        referenceIndexTask?.cancel()
        referenceIndex.clear()
        referenceIndexError = nil
        referenceIndexWarning = nil
        isIndexingReferences = true
        referenceIndexProgress = 0

        // Indexing prefers the free on-device model; Gemini is only a fallback
        // when Apple Intelligence is unavailable. Independent of which
        // provider answers chat questions.
        let availability = referenceIndexingAvailability
        guard availability.isAvailable else {
            isIndexingReferences = false
            referenceIndexError = referenceIndexUnavailableMessage(for: availability)
            return
        }

        let model = referenceIndexModel()

        referenceIndexTask = Task {
            // Give the UI a moment to show the indexing state, preventing
            // SwiftUI from missing the state change if the cache load is instantaneous.
            try? await Task.sleep(for: .milliseconds(150))
            
            do {
                let outcome = try await LLMReferenceIndexBuilder.build(
                    documentURL: url,
                    model: model
                ) { completed, total in
                    Task { @MainActor in
                        self.referenceIndexProgress = total > 0 ? Double(completed) / Double(total) : 1
                    }
                }

                guard !Task.isCancelled else { return }
                await MainActor.run {
                    referenceIndex.replace(with: outcome.snapshot)
                    isIndexingReferences = false
                    referenceIndexProgress = 1
                    referenceIndexError = nil
                    let failedCount = outcome.failedPageIndices.count
                    referenceIndexWarning = failedCount == 0 ? nil :
                        "\(failedCount) page\(failedCount == 1 ? "" : "s") could not be indexed — they'll be retried next time this document is opened."
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    referenceIndex.clear()
                    isIndexingReferences = false
                    referenceIndexProgress = 0
                    referenceIndexError = error.localizedDescription
                }
            }
        }
    }

    private var referenceIndexingAvailability: ReadingAssistantAvailability {
        let local = FoundationModelsReadingAssistantService.localAvailability
        if local.isAvailable {
            return local
        }
        if ModelProviderPreferences.geminiEnabled {
            return .available(.gemini)
        }
        return local
    }

    private func referenceIndexModel() -> any LanguageModel {
        if FoundationModelsReadingAssistantService.localAvailability.isAvailable {
            return SystemLanguageModel.default
        }
        if let apiKey = ModelProviderPreferences.activeGeminiAPIKey {
            return GeminiCloudLanguageModel(apiKey: apiKey)
        }
        return SystemLanguageModel.default
    }

    private func referenceIndexUnavailableMessage(for availability: ReadingAssistantAvailability) -> String {
        switch availability {
        case .available:
            "Reference indexing is unavailable."
        case .deviceNotEligible:
            "Reference indexing unavailable — this device does not support Apple Intelligence."
        case .intelligenceNotEnabled:
            "Reference indexing unavailable — enable Apple Intelligence or add a Gemini API key."
        case .modelNotReady:
            "Reference indexing unavailable — the on-device model is not ready."
        case .geminiKeyMissing:
            "Reference indexing unavailable — add a Gemini API key in Settings."
        case .cliNotInstalled:
            "Reference indexing unavailable — add a Gemini API key or enable Apple Intelligence."
        case .unavailable:
            "Reference indexing unavailable — add a Gemini API key or enable Apple Intelligence."
        }
    }

    private func stopSecurityScopedAccess() {
        referenceIndexTask?.cancel()
        referenceIndexTask = nil
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
    }
}
