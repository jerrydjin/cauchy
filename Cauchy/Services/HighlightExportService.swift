import Foundation
import PDFKit

enum HighlightExportError: LocalizedError {
    case cannotOpenSource
    case cannotWriteCopy

    var errorDescription: String? {
        switch self {
        case .cannotOpenSource:
            "The PDF could not be reopened to write the copy."
        case .cannotWriteCopy:
            "The annotated copy could not be written."
        }
    }
}

/// Gets a reading session out of the app: highlights and their conversations as
/// Markdown, or the PDF itself with the highlights painted in so they survive
/// in Preview and for whoever the file is sent to.
enum HighlightExportService {
    // MARK: - Markdown

    /// Highlights in reading order — page order, then when they were made —
    /// rather than the panel's most-recently-touched order, because a document
    /// read start to finish is what the export is a record of.
    nonisolated static func readingOrder(_ highlights: [Highlight]) -> [Highlight] {
        highlights.sorted {
            $0.pageIndex == $1.pageIndex
                ? $0.createdAt < $1.createdAt
                : $0.pageIndex < $1.pageIndex
        }
    }

    nonisolated static func markdown(
        documentTitle: String,
        highlights: [Highlight],
        exportedAt: Date = Date()
    ) -> String {
        let ordered = readingOrder(highlights)
        var out = "# \(documentTitle)\n\n"

        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        let count = ordered.count == 1 ? "1 highlight" : "\(ordered.count) highlights"
        out += "*\(count) · exported from Cauchy on \(formatter.string(from: exportedAt))*\n"

        for highlight in ordered {
            out += "\n---\n\n"
            out += body(of: highlight, headingLevel: 2)
        }
        return out
    }

    /// One thread on its own, for "Copy as Markdown" on a single row.
    nonisolated static func markdown(for highlight: Highlight, documentTitle: String) -> String {
        "# \(documentTitle)\n\n" + body(of: highlight, headingLevel: 2)
    }

    nonisolated private static func body(of highlight: Highlight, headingLevel: Int) -> String {
        let hashes = String(repeating: "#", count: headingLevel)
        var out = "\(hashes) \(highlight.displayName)\n\n"
        out += "**Page \(highlight.pageIndex + 1)**"
        if highlight.color != .default {
            out += " · \(highlight.color.displayName)"
        }
        out += "\n\n"

        let passage = highlight.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !passage.isEmpty {
            out += blockQuote(passage) + "\n\n"
        }

        if let note = highlight.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            out += "**Note:** \(note)\n\n"
        }

        for message in highlight.messages {
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            switch message.role {
            case .user:
                out += "**Q:** \(content)\n\n"
            case .assistant:
                out += "\(content)\n\n"
            }
        }
        return out
    }

    /// Every line prefixed, so a passage that wrapped across several lines in
    /// the PDF stays one quote instead of breaking out of it half way down.
    nonisolated private static func blockQuote(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { $0.isEmpty ? ">" : "> \($0)" }
            .joined(separator: "\n")
    }

    // MARK: - Annotated PDF

    /// Writes a copy of the PDF with the highlights painted into it. Reopens
    /// the file rather than reusing the live `PDFDocument`, so the copy carries
    /// no selection state and the reader's own document is never touched.
    nonisolated static func writeAnnotatedPDF(
        source: URL,
        destination: URL,
        highlights: [Highlight]
    ) throws {
        guard let document = PDFDocument(url: source) else {
            throw HighlightExportError.cannotOpenSource
        }
        // No active highlight: in an exported copy every highlight is equal,
        // and the stronger active tint would read as a mistake.
        HighlightAnnotationService.sync(document: document, highlights: highlights, activeID: nil)
        guard document.write(to: destination) else {
            throw HighlightExportError.cannotWriteCopy
        }
    }
}
