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
    /// Stemmed name-token sets per entry, for "definition of compactness"-style
    /// questions against v4 caches that carry printed names.
    private var termIndex: [(nameStems: Set<String>, key: ReferenceKey)] = []
    /// Stemmed tokens of each entry's searchable text, plus per-stem document
    /// frequency — the lexical body route ("definition of continuity" →
    /// definition-kind entries whose body talks about continuous maps).
    private var bodyStems: [ReferenceKey: Set<String>] = [:]
    private var stemDocumentFrequency: [String: Int] = [:]

    func lookup(_ reference: DetectedReference) -> IndexedReference? {
        entries[reference.key]
    }

    var isEmpty: Bool { entries.isEmpty }

    func replace(with snapshot: DocumentReferenceIndexSnapshot) {
        entries = snapshot.entries
        bodyEmbeddings = snapshot.bodyEmbeddings ?? [:]
        termIndex = snapshot.entries.compactMap { key, entry in
            guard let name = entry.name else { return nil }
            let stems = Set(LexicalDocumentIndex.tokenize(name).map(Self.stem))
            guard !stems.isEmpty else { return nil }
            return (nameStems: stems, key: key)
        }

        bodyStems = [:]
        stemDocumentFrequency = [:]
        for (key, entry) in snapshot.entries {
            let text = DocumentReferenceIndexSnapshot.searchableText(for: entry)
            let stems = Set(LexicalDocumentIndex.tokenize(text).map(Self.stem))
            bodyStems[key] = stems
            for stem in stems {
                stemDocumentFrequency[stem, default: 0] += 1
            }
        }
    }

    func clear() {
        entries = [:]
        bodyEmbeddings = [:]
        termIndex = []
        bodyStems = [:]
        stemDocumentFrequency = [:]
    }

    /// Crude prefix stem so inflections meet: "continuity"/"continuous" →
    /// "contin", "compactness"/"compact" → "compac".
    nonisolated static func stem(_ token: String) -> String {
        token.count > 6 ? String(token.prefix(6)) : token
    }

    /// Diagnostic (probe CLI): the highest-similarity entries with their raw
    /// cosine scores, ungated.
    func semanticCandidates(for queryVector: [Float], limit: Int) -> [(heading: String, similarity: Double)] {
        bodyEmbeddings
            .map { key, vector in
                (key: key, similarity: SentenceEmbedder.cosineSimilarity(queryVector, vector))
            }
            .sorted { $0.similarity > $1.similarity }
            .prefix(limit)
            .compactMap { scored in
                entries[scored.key].map { ($0.promptHeading, scored.similarity) }
            }
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

    /// Kind keywords a question can name ("the definition of…", "which
    /// theorem…"). Detecting one focuses the lexical body route on that kind.
    private static let kindIntentStems: [String: ReferenceKind] = [
        "define": .definition, "defini": .definition, "defines": .definition,
        "theore": .theorem, "lemma": .lemma, "lemmas": .lemma,
        "propos": .proposition, "coroll": .corollary,
        "exampl": .example, "remark": .remark, "equati": .equation,
    ]

    /// Statements whose printed name appears in the question ("how does this
    /// tie in with the definition of compactness" → Definition 3.2 (Compactness)).
    /// With definitional intent, definitions rank before other kinds.
    func statements(matchingTermsIn question: String) -> [IndexedReference] {
        let questionStems = Set(LexicalDocumentIndex.tokenize(question).map(Self.stem))
        guard !questionStems.isEmpty else { return [] }
        let definitionalIntent = kindFocus(in: questionStems) == .definition

        let matches = termIndex.filter { $0.nameStems.isSubset(of: questionStems) }
        return matches
            .sorted { a, b in
                if definitionalIntent {
                    let aIsDefinition = a.key.kind == .definition
                    let bIsDefinition = b.key.kind == .definition
                    if aIsDefinition != bIsDefinition { return aIsDefinition }
                }
                // More specific (longer) names first.
                return a.nameStems.count > b.nameStems.count
            }
            .compactMap { entries[$0.key] }
    }

    /// Lexical fallback when names are unavailable (migrated caches) or don't
    /// match: score statement bodies by rarity-weighted overlap with the
    /// question's stems, focused on the kind the question names. Ties break
    /// toward earlier pages — the defining occurrence of a term precedes its
    /// uses.
    func statements(lexicallyMatching question: String, limit: Int) -> [IndexedReference] {
        guard !bodyStems.isEmpty, limit > 0 else { return [] }
        let focus = kindFocus(in: Set(LexicalDocumentIndex.tokenize(question).map(Self.stem)))
        // Only mathematical content selects a statement — never the kind word
        // ("definition") or question function words ("how does this tie in…").
        let questionStems = contentStems(of: question)
        guard !questionStems.isEmpty else { return [] }

        // Only stems that actually discriminate: a stem shared by most entries
        // (or by none) says nothing about which statement is meant.
        let dfCeiling = max(3, entries.count / 4)

        var scored: [(key: ReferenceKey, score: Double, pageIndex: Int)] = []
        for (key, stems) in bodyStems {
            if let focus, key.kind != focus { continue }
            var score = 0.0
            for stem in questionStems.intersection(stems) {
                let df = stemDocumentFrequency[stem] ?? 0
                guard df > 0, df <= dfCeiling else { continue }
                score += 1.0 / Double(df)
            }
            if score > 0, let entry = entries[key] {
                scored.append((key, score, entry.pageIndex))
            }
        }

        return scored
            .sorted { a, b in
                if a.score != b.score { return a.score > b.score }
                return a.pageIndex < b.pageIndex
            }
            .prefix(limit)
            .compactMap { entries[$0.key] }
    }

    /// Post-stem stopwords: English function words and question-meta verbs.
    /// Chosen to avoid colliding with mathematical vocabulary after 6-char
    /// stemming ("connec"(ted) and "relati"(on) are content; "relate" is not).
    private static let questionStopStems: Set<String> = [
        "how", "does", "do", "did", "what", "which", "why", "when", "where", "who",
        "the", "an", "of", "in", "on", "with", "to", "from", "into", "onto",
        "is", "are", "was", "were", "be", "been", "being",
        "this", "that", "these", "those", "it", "its",
        "and", "or", "not", "as", "at", "by", "for", "about",
        "we", "you", "me", "my", "our", "your",
        "can", "could", "should", "would", "will", "shall", "may", "might", "must",
        "tie", "ties", "tied", "relate", "explain", "tell", "show", "help",
        "please", "here", "there", "used", "use", "using",
        // "mean value" loses one stem here, but question-side "what does it
        // mean" noise outweighs that (bodies keep their own words regardless).
        "mean", "means", "meant",
    ]

    /// Question stems that carry mathematical content: stemmed, minus kind
    /// words and function words.
    private func contentStems(of question: String) -> Set<String> {
        var stems = Set(LexicalDocumentIndex.tokenize(question).map(Self.stem))
        stems.subtract(Self.kindIntentStems.keys)
        stems.subtract(Self.questionStopStems)
        return stems
    }

    private func kindFocus(in questionStems: Set<String>) -> ReferenceKind? {
        for (stem, kind) in Self.kindIntentStems where questionStems.contains(stem) {
            return kind
        }
        return nil
    }

    /// Statements whose body is semantically close to the query embedding.
    /// Contextual-embedding similarities cluster in a narrow band (~0.85–0.91
    /// measured), so gating is adaptive (outliers above the document's own
    /// similarity distribution) AND lexically corroborated: an entry must share
    /// at least one content stem with the question, which keeps off-topic
    /// queries from surfacing whatever happens to rank highest.
    func statements(
        semanticallyMatching queryVector: [Float],
        question: String,
        limit: Int
    ) -> [IndexedReference] {
        guard !bodyEmbeddings.isEmpty, limit > 0 else { return [] }
        let questionStems = contentStems(of: question)
        let scored = bodyEmbeddings.compactMap { key, vector -> (key: ReferenceKey, similarity: Double)? in
            guard let stems = bodyStems[key], !stems.isDisjoint(with: questionStems) else { return nil }
            return (key: key, similarity: SentenceEmbedder.cosineSimilarity(queryVector, vector))
        }
        guard !scored.isEmpty else { return [] }

        let similarities = scored.map(\.similarity)
        let mean = similarities.reduce(0, +) / Double(similarities.count)
        let variance = similarities.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(similarities.count)
        let threshold = scored.count >= 8
            ? max(0.8, mean + 1.5 * variance.squareRoot())
            : 0.88

        return scored
            .filter { $0.similarity >= threshold }
            .sorted { $0.similarity > $1.similarity }
            .prefix(limit)
            .compactMap { entries[$0.key] }
    }
}
