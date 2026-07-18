import Foundation
import NaturalLanguage

/// Thin wrapper around Apple's on-device sentence embedding. NLEmbedding is
/// not Sendable, so background index builds create their own instance
/// (`makeModel()`), while ask-time query embedding goes through the
/// main-actor-cached `queryVector(for:)`.
enum SentenceEmbedder {
    /// The embedding model input degrades on very long text; clip before embedding.
    static let maxInputCharacters = 1_000

    nonisolated static func makeModel() -> NLEmbedding? {
        NLEmbedding.sentenceEmbedding(for: .english)
    }

    nonisolated static func vector(for text: String, using model: NLEmbedding) -> [Float]? {
        let clipped = String(text.prefix(maxInputCharacters))
        let trimmed = clipped.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let vector = model.vector(for: trimmed) else { return nil }
        return vector.map(Float.init)
    }

    @MainActor private static var cachedQueryModel: NLEmbedding?
    @MainActor private static var queryModelLoadAttempted = false

    /// Embeds an ask-time query with a lazily loaded, cached model (loading the
    /// model is the expensive part; a vector is ~1 ms).
    @MainActor
    static func queryVector(for text: String) -> [Float]? {
        if !queryModelLoadAttempted {
            queryModelLoadAttempted = true
            cachedQueryModel = makeModel()
        }
        guard let model = cachedQueryModel else { return nil }
        return vector(for: text, using: model)
    }

    nonisolated static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Double = 0
        var normA: Double = 0
        var normB: Double = 0
        for i in a.indices {
            let x = Double(a[i])
            let y = Double(b[i])
            dot += x * y
            normA += x * x
            normB += y * y
        }
        guard normA > 0, normB > 0 else { return 0 }
        return dot / ((normA * normB).squareRoot())
    }

    /// Strips LaTeX delimiters and commands so embeddings see the prose and
    /// symbol names rather than markup.
    nonisolated static func plainText(fromLaTeX text: String) -> String {
        var result = text
        for token in ["$$", "$", "\\left", "\\right", "{", "}"] {
            result = result.replacingOccurrences(of: token, with: " ")
        }
        result = result.replacingOccurrences(
            of: #"\\[a-zA-Z]+"#,
            with: " ",
            options: .regularExpression
        )
        return result.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)
    }
}
