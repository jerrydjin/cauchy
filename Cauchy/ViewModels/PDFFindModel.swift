import AppKit
import Foundation
import Observation
import PDFKit

@MainActor
@Observable
final class PDFFindModel: NSObject {
    private(set) var isVisible = false
    private(set) var matches: [PDFSelection] = []
    private(set) var currentIndex: Int?
    /// True while an asynchronous document find is streaming in matches.
    private(set) var isSearching = false
    /// Bumped whenever the highlighted selections shown by the PDF view must be
    /// reapplied (new results, new active match, or cleared).
    private(set) var revision = UUID()
    /// Bumped when the find field should grab keyboard focus again.
    private(set) var focusRequest = UUID()
    /// Set by the designer snapshot so the bar can show a match count without
    /// a PDF document. Production searches leave this nil.
    private(set) var snapshotMatchCount: Int?

    var query = "" {
        didSet {
            guard query != oldValue, !suppressSearch else { return }
            scheduleSearch()
        }
    }

    /// Set while `showPlainSnapshot` assigns `query`, so the assignment does
    /// not start a document search.
    private var suppressSearch = false

    /// Supplies the page currently on screen so a fresh search starts from
    /// there rather than page 1, matching Preview's behavior.
    var currentPageProvider: (() -> Int)?

    private weak var document: PDFDocument?
    private var searchTask: Task<Void, Never>?
    /// Matches streamed by the in-flight find; committed to `matches` when the
    /// find ends so the UI never sees a half-populated result list.
    private var pendingMatches: [PDFSelection] = []

    var activeMatch: PDFSelection? {
        guard let currentIndex, matches.indices.contains(currentIndex) else { return nil }
        return matches[currentIndex]
    }

    var hasMatches: Bool { !matches.isEmpty || (snapshotMatchCount ?? 0) > 0 }

    var matchCount: Int { snapshotMatchCount ?? matches.count }

    func attach(to document: PDFDocument?) {
        searchTask?.cancel()
        cancelInFlightSearch()
        if self.document?.delegate === self {
            self.document?.delegate = nil
        }
        self.document = document
        document?.delegate = self
        isVisible = false
        query = ""
        clearMatches()
    }

    func present() {
        isVisible = true
        focusRequest = UUID()
        if !query.isEmpty && matches.isEmpty {
            runSearch()
        }
    }

    /// Shows the plain find bar with a match count and no PDF. Typing still searches.
    func showPlainSnapshot(query snapshotQuery: String, matchCount: Int) {
        searchTask?.cancel()
        cancelInFlightSearch()
        isVisible = true
        isSearching = false
        matches = []
        currentIndex = nil
        snapshotMatchCount = matchCount
        suppressSearch = true
        query = snapshotQuery
        suppressSearch = false
    }

    func dismiss() {
        searchTask?.cancel()
        cancelInFlightSearch()
        isVisible = false
        clearMatches()
    }

    func findNext() {
        guard !matches.isEmpty else { return }
        select(index: ((currentIndex ?? -1) + 1) % matches.count)
    }

    func findPrevious() {
        guard !matches.isEmpty else { return }
        select(index: ((currentIndex ?? 0) - 1 + matches.count) % matches.count)
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        guard !query.isEmpty else {
            cancelInFlightSearch()
            clearMatches()
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.runSearch()
        }
    }

    /// Kicks off PDFKit's asynchronous find, which walks the document on a
    /// background thread and reports matches through the delegate — so typing
    /// in the find bar never blocks the UI, even on very large documents.
    func activate(_ hit: DocumentFind.Hit) {
        guard let selection = selection(onPage: hit.pageIndex, matching: hit.anchor) else { return }
        matches = [selection]
        select(index: 0)
    }

    private func runSearch() {
        guard let document, !query.isEmpty else {
            clearMatches()
            return
        }

        snapshotMatchCount = nil
        cancelInFlightSearch()
        pendingMatches = []
        isSearching = true
        document.beginFindString(query, withOptions: [.caseInsensitive, .diacriticInsensitive])
    }

    private func selection(onPage pageIndex: Int, matching anchor: String) -> PDFSelection? {
        guard let document, let page = document.page(at: pageIndex), let text = page.string else { return nil }
        let source = text as NSString
        guard source.length > 0 else { return nil }
        let found = source.range(of: anchor, options: [.caseInsensitive])
        let range = found.location == NSNotFound
            ? NSRange(location: 0, length: 1)
            : found
        return page.selection(for: range)
    }

    private func cancelInFlightSearch() {
        guard isSearching else { return }
        document?.cancelFindString()
        pendingMatches = []
        isSearching = false
    }

    private func finishSearch() {
        guard isSearching else { return }
        isSearching = false
        let textMatches = pendingMatches
        pendingMatches = []
        matches = textMatches
        if matches.isEmpty {
            currentIndex = nil
            revision = UUID()
        } else if let document {
            select(index: startIndex(for: matches, in: document))
        }
    }

    /// First match on or after the page the reader is currently viewing.
    private func startIndex(for matches: [PDFSelection], in document: PDFDocument) -> Int {
        guard let currentPage = currentPageProvider?(), currentPage > 0 else { return 0 }
        for (index, selection) in matches.enumerated() {
            guard let page = selection.pages.first else { continue }
            if document.index(for: page) >= currentPage {
                return index
            }
        }
        return 0
    }

    private func select(index: Int) {
        currentIndex = index
        for (i, selection) in matches.enumerated() {
            selection.color = i == index
                ? NSColor.systemOrange
                : NSColor.systemYellow.withAlphaComponent(0.5)
        }
        revision = UUID()
    }

    private func clearMatches() {
        matches = []
        currentIndex = nil
        snapshotMatchCount = nil
        revision = UUID()
    }
}

/// Cmd-K catalogue of indexed statements. Filtering reuses `DocumentFind`.
@MainActor
@Observable
final class JumpPaletteModel {
    private(set) var isVisible = false
    private(set) var hits: [DocumentFind.Hit] = []
    private(set) var selection = 0
    private(set) var focusRequest = UUID()
    var isIndexing = false

    var query = "" {
        didSet {
            guard query != oldValue, !suppressRefresh else { return }
            selection = 0
            refresh()
        }
    }

    var source: (() -> DocumentFind.Source?)?
    var onJump: ((DocumentFind.Hit) -> Void)?

    private var suppressRefresh = false

    func present() {
        isVisible = true
        suppressRefresh = true
        query = ""
        suppressRefresh = false
        selection = 0
        refresh()
        focusRequest = UUID()
    }

    func dismiss() {
        isVisible = false
        suppressRefresh = true
        query = ""
        suppressRefresh = false
        hits = []
        selection = 0
    }

    func move(_ delta: Int) {
        guard !hits.isEmpty else { return }
        selection = min(max(selection + delta, 0), hits.count - 1)
    }

    func jumpSelected() {
        guard hits.indices.contains(selection) else { return }
        let hit = hits[selection]
        onJump?(hit)
        dismiss()
    }

    func jump(_ hit: DocumentFind.Hit) {
        if let index = hits.firstIndex(where: { $0.id == hit.id }) {
            selection = index
        }
        onJump?(hit)
        dismiss()
    }

    func refresh() {
        guard let source = source?() else {
            hits = []
            selection = 0
            return
        }
        hits = DocumentFind.jumpHits(
            query: query,
            entries: source.entries,
            sections: DocumentFind.sections(in: source.pages)
        )
        if selection >= hits.count { selection = 0 }
    }

    func refreshIfVisible() {
        guard isVisible else { return }
        let selectedID = hits.indices.contains(selection) ? hits[selection].id : nil
        refresh()
        if let selectedID, let index = hits.firstIndex(where: { $0.id == selectedID }) {
            selection = index
        } else {
            selection = 0
        }
    }

    /// Draws the palette from finished hits. Assigning `query` does not search.
    func showSnapshot(query snapshotQuery: String, hits snapshotHits: [DocumentFind.Hit], selection index: Int = 0) {
        isVisible = true
        isIndexing = false
        suppressRefresh = true
        query = snapshotQuery
        suppressRefresh = false
        hits = snapshotHits
        selection = snapshotHits.isEmpty ? 0 : min(max(index, 0), snapshotHits.count - 1)
        focusRequest = UUID()
    }
}

// PDFKit delivers these on the main thread; the methods are nonisolated only
// because PDFDocumentDelegate is not MainActor-annotated.
extension PDFFindModel: PDFDocumentDelegate {
    nonisolated func didMatchString(_ instance: PDFSelection) {
        // assumeIsolated is sound here (PDFKit calls this on the main thread),
        // and the selection never leaves the main actor afterwards.
        nonisolated(unsafe) let selection = instance
        MainActor.assumeIsolated {
            guard isSearching else { return }
            pendingMatches.append(selection)
        }
    }

    nonisolated func documentDidEndDocumentFind(_ notification: Notification) {
        MainActor.assumeIsolated {
            finishSearch()
        }
    }
}
