import Foundation
import PDFKit

/// Immutable hybrid index over paragraph-sized chunks of the document, built
/// once per document off the main thread: BM25 always, fused with on-device
/// sentence embeddings when the embedding model is available. Powers ask-time
/// retrieval so the assistant can see relevant passages from pages other than
/// the selection.
struct LexicalDocumentIndex: DocumentIndexProtocol, Sendable {
    private struct Chunk: Sendable {
        let pageIndex: Int
        let text: String
        let termFrequencies: [String: Int]
        let tokenCount: Int
    }

    private let chunks: [Chunk]
    /// Parallel to `chunks`; nil when the embedding model was unavailable at
    /// build time (retrieval is then lexical-only). Individual entries are nil
    /// when a single chunk failed to embed.
    private let chunkEmbeddings: [[Float]?]?
    private let documentFrequencies: [String: Int]
    private let averageTokenCount: Double

    private static let k1 = 1.5
    private static let b = 0.75
    /// Reciprocal Rank Fusion constant (standard choice).
    private static let rrfK = 60.0

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

        // Embeddings are best-effort: no model, no semantic ranking — never
        // fail the build over it.
        var chunkEmbeddings: [[Float]?]?
        if let model = SentenceEmbedder.makeModel() {
            chunkEmbeddings = chunks.map { SentenceEmbedder.vector(for: $0.text, using: model) }
        }

        return LexicalDocumentIndex(
            chunks: chunks,
            chunkEmbeddings: chunkEmbeddings,
            documentFrequencies: documentFrequencies,
            averageTokenCount: averageTokenCount
        )
    }

    func passages(matching query: String, limit: Int, excludingPage: Int?) -> [String] {
        passages(matching: query, queryVector: nil, limit: limit, excludingPage: excludingPage)
    }

    func passages(
        matching query: String,
        queryVector: [Float]?,
        limit: Int,
        excludingPage: Int?
    ) -> [String] {
        guard limit > 0 else { return [] }
        let lexicalRanking = lexicalRanking(query: query, excludingPage: excludingPage)

        guard let queryVector, chunkEmbeddings != nil else {
            return format(Array(lexicalRanking.prefix(limit)))
        }
        let semanticRanking = semanticRanking(queryVector: queryVector, excludingPage: excludingPage)
        guard !semanticRanking.isEmpty else {
            return format(Array(lexicalRanking.prefix(limit)))
        }

        // Reciprocal Rank Fusion: robust to the incomparable score scales of
        // BM25 and cosine similarity.
        var fused: [Int: Double] = [:]
        for (rank, chunkIndex) in lexicalRanking.enumerated() {
            fused[chunkIndex, default: 0] += 1 / (Self.rrfK + Double(rank + 1))
        }
        for (rank, chunkIndex) in semanticRanking.enumerated() {
            fused[chunkIndex, default: 0] += 1 / (Self.rrfK + Double(rank + 1))
        }

        let top = fused
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map(\.key)
        return format(top)
    }

    /// Chunk indices ranked by BM25 score, best first (positive scores only).
    private func lexicalRanking(query: String, excludingPage: Int?) -> [Int] {
        let queryTerms = Set(Self.tokenize(query))
        guard !queryTerms.isEmpty else { return [] }

        let totalChunks = Double(chunks.count)
        var scored: [(index: Int, score: Double)] = []
        for (index, chunk) in chunks.enumerated() {
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
                scored.append((index, score))
            }
        }
        return scored.sorted { $0.score > $1.score }.map(\.index)
    }

    /// Chunk indices ranked by cosine similarity, best first, capped so weak
    /// tail matches can't pile up RRF contributions. (Contextual-embedding
    /// similarities sit in a narrow band, so absolute floors are meaningless —
    /// only the ranking is trustworthy.)
    private func semanticRanking(queryVector: [Float], excludingPage: Int?) -> [Int] {
        guard let chunkEmbeddings else { return [] }
        var scored: [(index: Int, similarity: Double)] = []
        for (index, embedding) in chunkEmbeddings.enumerated() {
            guard let embedding else { continue }
            if let excludingPage, chunks[index].pageIndex == excludingPage { continue }
            scored.append((index, SentenceEmbedder.cosineSimilarity(queryVector, embedding)))
        }
        return scored
            .sorted { $0.similarity > $1.similarity }
            .prefix(30)
            .map(\.index)
    }

    private func format(_ chunkIndices: [Int]) -> [String] {
        chunkIndices.map { "[p. \(chunks[$0].pageIndex + 1)] \(chunks[$0].text)" }
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
