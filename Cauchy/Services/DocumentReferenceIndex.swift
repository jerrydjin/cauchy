import Foundation
import PDFKit

struct DocumentReferenceIndexSnapshot: Sendable {
    let entries: [ReferenceKey: IndexedReference]
    let pageCount: Int
    /// Embedding of each entry's searchable text (name + de-LaTeXed body);
    /// nil when the on-device embedding model is unavailable.
    let bodyEmbeddings: [ReferenceKey: [Float]]?

    init(
        entries: [ReferenceKey: IndexedReference],
        pageCount: Int,
        bodyEmbeddings: [ReferenceKey: [Float]]? = nil
    ) {
        self.entries = entries
        self.pageCount = pageCount
        self.bodyEmbeddings = bodyEmbeddings
    }

    /// Computes body embeddings for a finished entry set. Called from the
    /// background build/load path so the main-actor `replace(with:)` stays cheap.
    nonisolated static func computeBodyEmbeddings(
        for entries: [ReferenceKey: IndexedReference]
    ) -> [ReferenceKey: [Float]]? {
        guard let model = SentenceEmbedder.makeModel() else { return nil }
        var result: [ReferenceKey: [Float]] = [:]
        for (key, entry) in entries {
            if let vector = SentenceEmbedder.vector(for: searchableText(for: entry), using: model) {
                result[key] = vector
            }
        }
        return result.isEmpty ? nil : result
    }

    nonisolated static func searchableText(for entry: IndexedReference) -> String {
        let heading = [entry.reference.kind.displayName, entry.name ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return heading + ". " + SentenceEmbedder.plainText(fromLaTeX: entry.formattedBody)
    }
}

/// Lookup table for indexed references. Built off-main by
/// LLMReferenceIndexBuilder (which hands over an immutable snapshot), but only
/// ever read and mutated on the main actor (WorkspaceViewModel, PDFCanvasView
/// hover detection, ask-time statement retrieval).
@MainActor
final class DocumentReferenceIndex {
    private var entries: [ReferenceKey: IndexedReference] = [:]
    private var bodyEmbeddings: [ReferenceKey: [Float]] = [:]
    /// name-token sets per entry, for "definition of compactness"-style questions.
    private var termIndex: [(nameTokens: Set<String>, key: ReferenceKey)] = []

    func lookup(_ reference: DetectedReference) -> IndexedReference? {
        entries[reference.key]
    }

    var isEmpty: Bool { entries.isEmpty }

    func replace(with snapshot: DocumentReferenceIndexSnapshot) {
        entries = snapshot.entries
        bodyEmbeddings = snapshot.bodyEmbeddings ?? [:]
        termIndex = snapshot.entries.compactMap { key, entry in
            guard let name = entry.name else { return nil }
            let tokens = Set(LexicalDocumentIndex.tokenize(name))
            guard !tokens.isEmpty else { return nil }
            return (nameTokens: tokens, key: key)
        }
    }

    func clear() {
        entries = [:]
        bodyEmbeddings = [:]
        termIndex = []
    }

    // MARK: - Ask-time statement retrieval

    /// Statements explicitly cited ("Definition 3.2", "(4.1)") anywhere in the
    /// given texts, in citation order, deduped.
    func statements(citedIn texts: [String]) -> [IndexedReference] {
        var seen = Set<ReferenceKey>()
        var results: [IndexedReference] = []
        for text in texts {
            for match in ReferenceDetector.allReferences(in: text) {
                let key = match.reference.key
                guard !seen.contains(key), let entry = entries[key] else { continue }
                seen.insert(key)
                results.append(entry)
            }
        }
        return results
    }

    private static let definitionalIntentTokens: Set<String> = [
        "define", "defined", "definition", "defines", "meaning", "means",
    ]

    /// Statements whose printed name appears in the question ("how does this
    /// tie in with the definition of compactness" → Definition 3.2 (Compactness)).
    /// With definitional intent, definitions rank before other kinds.
    func statements(matchingTermsIn question: String) -> [IndexedReference] {
        let questionTokens = Set(LexicalDocumentIndex.tokenize(question))
        guard !questionTokens.isEmpty else { return [] }
        let definitionalIntent = !questionTokens.isDisjoint(with: Self.definitionalIntentTokens)

        let matches = termIndex.filter { $0.nameTokens.isSubset(of: questionTokens) }
        return matches
            .sorted { a, b in
                if definitionalIntent {
                    let aIsDefinition = a.key.kind == .definition
                    let bIsDefinition = b.key.kind == .definition
                    if aIsDefinition != bIsDefinition { return aIsDefinition }
                }
                // More specific (longer) names first.
                return a.nameTokens.count > b.nameTokens.count
            }
            .compactMap { entries[$0.key] }
    }

    /// Statements whose body is semantically close to the query embedding.
    func statements(
        semanticallyMatching queryVector: [Float],
        limit: Int,
        minSimilarity: Double
    ) -> [IndexedReference] {
        guard !bodyEmbeddings.isEmpty, limit > 0 else { return [] }
        return bodyEmbeddings
            .map { key, vector in
                (key: key, similarity: SentenceEmbedder.cosineSimilarity(queryVector, vector))
            }
            .filter { $0.similarity >= minSimilarity }
            .sorted { $0.similarity > $1.similarity }
            .prefix(limit)
            .compactMap { entries[$0.key] }
    }
}
