import Foundation

/// One highlight, in whichever document it belongs to, that matched a
/// library-wide search.
struct LibrarySearchResult: Identifiable, Sendable {
    var id: UUID { highlight.id }
    var workspaceID: UUID
    var documentURL: URL
    var bookmarkData: Data?
    var highlight: Highlight
    /// The text around the match, for the result row — the passage is not
    /// always where the query was found.
    var snippet: String
}

/// Searches highlights and their conversations across every document in the
/// library. Deliberately scoped to what the reader wrote or asked, not to the
/// full text of every PDF: the per-document text indexes are built on open and
/// thrown away on close, so a library-wide full-text answer would be a promise
/// nothing on disk can keep.
enum LibrarySearchService {
    static func search(
        query: String,
        limit: Int = 200,
        persistence: DocumentPersistenceService = .shared
    ) async -> [LibrarySearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        let needle = trimmed.lowercased()

        let summaries = await persistence.listWorkspaceSummaries()
        var results: [LibrarySearchResult] = []

        for summary in summaries {
            guard summary.highlightCount > 0 else { continue }
            guard let persisted = await persistence.loadWorkspace(id: summary.workspaceID) else { continue }

            for highlight in HighlightExportService.readingOrder(persisted.workspace.highlights) {
                guard let snippet = match(highlight, needle: needle) else { continue }
                results.append(
                    LibrarySearchResult(
                        workspaceID: summary.workspaceID,
                        documentURL: persisted.workspace.documentURL,
                        bookmarkData: persisted.bookmarkData,
                        highlight: highlight,
                        snippet: snippet
                    )
                )
                if results.count >= limit { return results }
            }
        }
        return results
    }

    /// The first field of a highlight the query turns up in, as a snippet.
    /// Ordered by how much it tells the reader: what they asked or were told
    /// beats the raw passage, which beats the name derived from it.
    private static func match(_ highlight: Highlight, needle: String) -> String? {
        for message in highlight.messages where message.content.lowercased().contains(needle) {
            return snippet(around: needle, in: message.content)
        }
        if let note = highlight.note, note.lowercased().contains(needle) {
            return snippet(around: needle, in: note)
        }
        if highlight.selectedText.lowercased().contains(needle) {
            return snippet(around: needle, in: highlight.selectedText)
        }
        if highlight.displayName.lowercased().contains(needle) {
            return highlight.displayName
        }
        return nil
    }

    /// A window of text centred on the match, cut at word boundaries so the
    /// row never opens or closes mid-word.
    static func snippet(around needle: String, in text: String, radius: Int = 90) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard let range = collapsed.lowercased().range(of: needle) else {
            return String(collapsed.prefix(radius * 2))
        }

        let start = collapsed.index(
            range.lowerBound,
            offsetBy: -radius,
            limitedBy: collapsed.startIndex
        ) ?? collapsed.startIndex
        let end = collapsed.index(
            range.upperBound,
            offsetBy: radius,
            limitedBy: collapsed.endIndex
        ) ?? collapsed.endIndex

        var slice = String(collapsed[start..<end])
        if start != collapsed.startIndex {
            if let space = slice.firstIndex(of: " ") {
                slice = String(slice[slice.index(after: space)...])
            }
            slice = "…" + slice
        }
        if end != collapsed.endIndex {
            if let space = slice.lastIndex(of: " ") {
                slice = String(slice[..<space])
            }
            slice += "…"
        }
        return slice
    }
}
