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

    var query = "" {
        didSet {
            guard query != oldValue else { return }
            scheduleSearch()
        }
    }

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

    var hasMatches: Bool { !matches.isEmpty }

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
    private func runSearch() {
        guard let document, !query.isEmpty else {
            clearMatches()
            return
        }

        cancelInFlightSearch()
        pendingMatches = []
        isSearching = true
        document.beginFindString(query, withOptions: [.caseInsensitive, .diacriticInsensitive])
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
        matches = pendingMatches
        pendingMatches = []

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
        revision = UUID()
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
