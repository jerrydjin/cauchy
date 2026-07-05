import Foundation
import Observation

@MainActor
@Observable
final class HighlightStore {
    var highlights: [Highlight] = []
    var selectedHighlightID: UUID?
    var searchText: String = ""
    var pendingRegionCapture: SelectionCapture?

    var filteredHighlights: [Highlight] {
        guard !searchText.isEmpty else { return highlights.sorted { $0.updatedAt > $1.updatedAt } }
        let query = searchText.lowercased()
        return highlights.filter {
            $0.label.lowercased().contains(query) ||
            $0.selectedText.lowercased().contains(query)
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func add(_ highlight: Highlight) {
        highlights.append(highlight)
    }

    func remove(_ highlight: Highlight) {
        highlights.removeAll { $0.id == highlight.id }
        if selectedHighlightID == highlight.id {
            selectedHighlightID = nil
        }
    }

    func update(_ highlight: Highlight) {
        guard let index = highlights.firstIndex(where: { $0.id == highlight.id }) else { return }
        highlights[index] = highlight
    }

    func findMatchingHighlight(for context: TextSelectionContext) -> Highlight? {
        highlights.first { highlight in
            highlight.pageIndex == context.pageIndex &&
            highlight.selectedText == context.selectedText
        }
    }

    @discardableResult
    func upsertFromThread(_ thread: SelectionThread) -> Highlight {
        let now = Date()
        if let existingIndex = highlights.firstIndex(where: { $0.id == thread.anchorID }) {
            var highlight = highlights[existingIndex]
            highlight.selectedText = thread.selectedText
            highlight.surroundingText = thread.surroundingText
            highlight.bounds = thread.bounds ?? highlight.bounds
            highlight.lineBounds = thread.lineBounds ?? highlight.lineBounds
            highlight.messages = thread.messages
            highlight.updatedAt = now
            highlights[existingIndex] = highlight
            return highlight
        }

        let highlight = Highlight(
            id: thread.anchorID,
            pageIndex: thread.pageIndex,
            bounds: thread.bounds,
            lineBounds: thread.lineBounds,
            selectedText: thread.selectedText,
            surroundingText: thread.surroundingText,
            messages: thread.messages,
            isPinned: false,
            createdAt: now,
            updatedAt: now
        )
        highlights.append(highlight)
        return highlight
    }

    func pinHighlight(id: UUID) {
        guard var highlight = highlights.first(where: { $0.id == id }) else { return }
        highlight.isPinned = true
        highlight.updatedAt = Date()
        update(highlight)
    }

    func load(from workspace: DocumentWorkspace) {
        highlights = workspace.highlights
    }

    func exportToWorkspace(_ workspace: inout DocumentWorkspace) {
        workspace.highlights = highlights
    }
}
