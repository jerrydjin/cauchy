import Foundation
import NaturalLanguage

/// On-device text embeddings for ask-time retrieval, backed by Apple's
/// contextual (transformer) embedding. The static `NLEmbedding` sentence
/// vectors were measured to rank a "definition of continuity" query closer to
/// an unrelated definition than to the actual continuity lemma — contextual
/// embeddings order these correctly, at ~14 ms per chunk (fine for the
/// background index builds that call this).
///
/// The model type is not Sendable, so background builds create their own
/// instance (`makeModel()`), while ask-time query embedding goes through the
/// main-actor-cached `queryVector(for:)`.
enum SentenceEmbedder {
    /// The embedding degrades on very long text; clip before embedding.
    static let maxInputCharacters = 1_000

    final class Model {
        private let embedding: NLContextualEmbedding

        fileprivate init?() {
            guard let embedding = NLContextualEmbedding(language: .english) else { return nil }
            guard embedding.hasAvailableAssets else {
                // Kick off the system asset download so a future launch has
                // them; this launch just runs without semantic retrieval.
                embedding.requestAssets { _, _ in }
                return nil
            }
            guard (try? embedding.load()) != nil else { return nil }
            self.embedding = embedding
        }

        /// Mean-pooled token embedding of the (clipped) text.
        func vector(for text: String) -> [Float]? {
            let clipped = String(text.prefix(SentenceEmbedder.maxInputCharacters))
            let trimmed = clipped.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let result = try? embedding.embeddingResult(for: trimmed, language: .english)
            else { return nil }

            var sum = [Double](repeating: 0, count: embedding.dimension)
            var count = 0
            result.enumerateTokenVectors(in: trimmed.startIndex..<trimmed.endIndex) { vector, _ in
                for i in vector.indices {
                    sum[i] += vector[i]
                }
                count += 1
                return true
            }
            guard count > 0 else { return nil }
            return sum.map { Float($0 / Double(count)) }
        }
    }

    nonisolated static func makeModel() -> Model? {
        Model()
    }

    nonisolated static func vector(for text: String, using model: Model) -> [Float]? {
        model.vector(for: text)
    }

    @MainActor private static var cachedQueryModel: Model?
    @MainActor private static var queryModelLoadAttempted = false

    /// Embeds an ask-time query with a lazily loaded, cached model (loading the
    /// model is the expensive part; a vector is ~15 ms).
    @MainActor
    static func queryVector(for text: String) -> [Float]? {
        if !queryModelLoadAttempted {
            queryModelLoadAttempted = true
            cachedQueryModel = makeModel()
        }
        guard let model = cachedQueryModel else { return nil }
        return model.vector(for: text)
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
