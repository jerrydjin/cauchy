import Foundation
import PDFKit

/// Immutable BM25 index over paragraph-sized chunks of the document, built
/// once per document off the main thread. Powers ask-time retrieval so the
/// assistant can see relevant passages from pages other than the selection.
struct LexicalDocumentIndex: DocumentIndexProtocol, Sendable {
    private struct Chunk: Sendable {
        let pageIndex: Int
        let text: String
        let termFrequencies: [String: Int]
        let tokenCount: Int
    }

    private let chunks: [Chunk]
    private let documentFrequencies: [String: Int]
    private let averageTokenCount: Double

    private static let k1 = 1.5
    private static let b = 0.75

    /// Opens its own PDFDocument instance so background building never races
    /// the live PDFView (same pattern as LLMReferenceIndexBuilder).
    nonisolated static func build(documentURL: URL) -> LexicalDocumentIndex? {
        guard let document = PDFDocument(url: documentURL) else { return nil }

        var chunks: [Chunk] = []
        for pageIndex in 0..<document.pageCount {
            guard let text = document.page(at: pageIndex)?.string else { continue }
            for chunkText in chunkTexts(from: text) {
                let tokens = tokenize(chunkText)
                guard tokens.count >= 8 else { continue }
                var frequencies: [String: Int] = [:]
                for token in tokens {
                    frequencies[token, default: 0] += 1
                }
                chunks.append(Chunk(
                    pageIndex: pageIndex,
                    text: chunkText,
                    termFrequencies: frequencies,
                    tokenCount: tokens.count
                ))
            }
        }
        guard !chunks.isEmpty else { return nil }

        var documentFrequencies: [String: Int] = [:]
        for chunk in chunks {
            for term in chunk.termFrequencies.keys {
                documentFrequencies[term, default: 0] += 1
            }
        }
        let averageTokenCount = Double(chunks.reduce(0) { $0 + $1.tokenCount }) / Double(chunks.count)

        return LexicalDocumentIndex(
            chunks: chunks,
            documentFrequencies: documentFrequencies,
            averageTokenCount: averageTokenCount
        )
    }

    func passages(matching query: String, limit: Int, excludingPage: Int?) -> [String] {
        let queryTerms = Set(Self.tokenize(query))
        guard !queryTerms.isEmpty, limit > 0 else { return [] }

        let totalChunks = Double(chunks.count)
        var scored: [(score: Double, chunk: Chunk)] = []
        for chunk in chunks {
            if let excludingPage, chunk.pageIndex == excludingPage { continue }
            var score = 0.0
            for term in queryTerms {
                guard let frequency = chunk.termFrequencies[term],
                      let documentFrequency = documentFrequencies[term] else { continue }
                let idf = log((totalChunks - Double(documentFrequency) + 0.5) / (Double(documentFrequency) + 0.5) + 1)
                let tf = Double(frequency)
                let lengthNorm = 1 - Self.b + Self.b * Double(chunk.tokenCount) / averageTokenCount
                score += idf * tf * (Self.k1 + 1) / (tf + Self.k1 * lengthNorm)
            }
            if score > 0 {
                scored.append((score, chunk))
            }
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { "[p. \($0.chunk.pageIndex + 1)] \($0.chunk.text)" }
    }

    // MARK: - Chunking & tokenization

    /// Folds paragraphs (or bare lines, since PDF text layers often lack blank
    /// lines) into ~800-character chunks; oversized paragraphs are split.
    nonisolated static func chunkTexts(from pageText: String) -> [String] {
        let paragraphs = pageText
            .components(separatedBy: "\n\n")
            .flatMap { paragraph -> [String] in
                paragraph.count <= 1_200 ? [paragraph] : splitLongParagraph(paragraph)
            }

        var result: [String] = []
        var current = ""
        for paragraph in paragraphs {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if current.isEmpty {
                current = trimmed
            } else if current.count + trimmed.count + 1 <= 800 {
                current += "\n" + trimmed
            } else {
                result.append(current)
                current = trimmed
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result.filter { $0.count >= 80 }
    }

    private nonisolated static func splitLongParagraph(_ paragraph: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        for line in paragraph.split(separator: "\n") {
            if current.count + line.count + 1 > 800, !current.isEmpty {
                pieces.append(current)
                current = String(line)
            } else {
                current = current.isEmpty ? String(line) : current + "\n" + line
            }
        }
        if !current.isEmpty {
            pieces.append(current)
        }
        return pieces
    }

    nonisolated static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }
}
