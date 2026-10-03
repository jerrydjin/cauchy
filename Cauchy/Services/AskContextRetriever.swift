import Foundation

/// Everything retrieved for one ask, ready for prompt assembly. `statements`
/// are PDF-source excerpts from the notes (injected above
/// passages); `passages` are hybrid BM25/semantic chunks from elsewhere in the
/// document. Neither is stored in thread history or shown in the chat UI.
struct AskRetrieval: Sendable, Equatable {
    var statements: [String]
    /// Parallel to `statements`: which route surfaced each one ("cited",
    /// "term", "semantic"). Diagnostic only — never sent to the model.
    var statementRoutes: [String]
    /// Parallel to `statements`; retained only for strict PDF-region resolution.
    var statementReferences: [IndexedReference] = []
    var passages: [String]
    /// Parallel to `passages`; a record is anchorable only when its exact
    /// text-layer span survived the same prompt clipping as the passage.
    var passageRecords: [DocumentPassage] = []
    /// Resolved IDs supplied with the turn; all must open a real PDF region.
    var citableSources: [AnswerSourceAnchor] = []

    static let empty = AskRetrieval(statements: [], statementRoutes: [], passages: [])

    var isEmpty: Bool { statements.isEmpty && passages.isEmpty }

    /// One-based PDF pages Cauchy can prove were supplied in the retrieved
    /// blocks. The selected page is added separately by the thread model.
    var sourcePageNumbers: [Int] {
        let statementPages = statements.compactMap { Self.pageNumber(in: $0, marker: ", p. ") }
        let passagePages = passages.compactMap { Self.pageNumber(in: $0, marker: "[p. ") }
        return Array(Set(statementPages + passagePages)).sorted()
    }

    /// Mirror the prompt builder's exact item and character limits before an
    /// ask. Answer provenance is calculated from this value, so a page dropped
    /// for context-window space cannot appear among the supplied sources.
    func clippedForPrompt(provider: AssistantConnectorID) -> AskRetrieval {
        let budgets = ReadingPromptBuilder.evidenceBudgets(for: provider)
        let clippedStatements = ReadingPromptBuilder.clip(
            statements, to: budgets.statements
        ) ?? []
        let clippedPassages = ReadingPromptBuilder.clip(passages, to: budgets.passages) ?? []
        let clippedRecords = zip(clippedPassages, passageRecords).map { clipped, record in
            DocumentPassage(
                text: clipped,
                location: clipped == record.text ? record.location : nil
            )
        }
        return AskRetrieval(
            statements: clippedStatements,
            statementRoutes: Array(statementRoutes.prefix(clippedStatements.count)),
            statementReferences: Array(statementReferences.prefix(clippedStatements.count)),
            passages: clippedPassages,
            passageRecords: clippedRecords
        )
    }

    private static func pageNumber(in text: String, marker: String) -> Int? {
        guard let markerRange = text.range(of: marker) else { return nil }
        let suffix = text[markerRange.upperBound...]
        let digits = suffix.prefix { $0.isNumber }
        return Int(digits)
    }
}

/// Combines the three statement routes with hybrid passage retrieval.
/// Priority: explicit citations → printed-name matches → semantic matches,
/// deduped by reference key, capped so statements can't crowd out the
/// question in small context windows.
@MainActor
enum AskContextRetriever {
    static let maxStatements = 4

    static func retrieve(
        question: String,
        selectedText: String,
        surroundingText: String,
        pageIndex: Int?,
        referenceIndex: DocumentReferenceIndex?,
        documentIndex: (any DocumentIndexProtocol)?,
        passageLimit: Int
    ) -> AskRetrieval {
        let query = question + " " + selectedText.prefix(200)
        let queryVector = SentenceEmbedder.queryVector(for: query)

        var collected: [(entry: IndexedReference, route: String)] = []
        var seen = Set<ReferenceKey>()

        func add(_ entries: [IndexedReference], route: String, cap: Int = .max) {
            var added = 0
            for entry in entries {
                guard added < cap, collected.count < maxStatements else { return }
                let key = entry.reference.key
                guard !seen.contains(key), !entry.groundingBody.isEmpty else { continue }
                seen.insert(key)
                collected.append((entry, route))
                added += 1
            }
        }

        if let referenceIndex, !referenceIndex.isEmpty {
            // Question and selection citations take slots before surrounding-text
            // ones (the surrounding prose often cites many nearby results).
            add(referenceIndex.statements(citedIn: [question, selectedText, surroundingText]), route: "cited")
            add(referenceIndex.statements(matchingTermsIn: question), route: "term", cap: 2)
            add(referenceIndex.statements(lexicallyMatching: question, limit: 2), route: "body", cap: 2)
            if let queryVector {
                add(
                    referenceIndex.statements(semanticallyMatching: queryVector, question: question, limit: 2),
                    route: "semantic",
                    cap: 2
                )
            }
        }

        var passageRecords: [DocumentPassage] = []
        if let documentIndex, passageLimit > 0 {
            passageRecords = documentIndex.passageRecords(
                matching: query,
                queryVector: queryVector,
                limit: passageLimit,
                excludingPage: pageIndex
            )
        }

        // A passage that substantially repeats an injected statement wastes budget.
        let statementBodies = collected.map { collapseWhitespace($0.entry.groundingBody) }
        passageRecords = passageRecords.filter { passage in
            let normalized = collapseWhitespace(passage.text)
            return !statementBodies.contains { body in
                let probe = String(body.prefix(80))
                return probe.count >= 40 && normalized.contains(probe)
            }
        }

        return AskRetrieval(
            statements: collected.map {
                let scope = $0.entry.reference.kind == .figure
                    ? "PDF caption heading only; image not interpreted"
                    : "PDF source excerpt"
                return "\($0.entry.promptHeading) [\(scope)]:\n\($0.entry.groundingBody)"
            },
            statementRoutes: collected.map(\.route),
            statementReferences: collected.map(\.entry),
            passages: passageRecords.map(\.text),
            passageRecords: passageRecords
        )
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
