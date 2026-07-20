import Foundation

/// Everything retrieved for one ask, ready for prompt assembly. `statements`
/// are exact reference statements from the notes (ground truth, injected above
/// passages); `passages` are hybrid BM25/semantic chunks from elsewhere in the
/// document. Neither is stored in thread history or shown in the chat UI.
struct AskRetrieval: Sendable, Equatable {
    var statements: [String]
    /// Parallel to `statements`: which route surfaced each one ("cited",
    /// "term", "semantic"). Diagnostic only — never sent to the model.
    var statementRoutes: [String]
    var passages: [String]

    static let empty = AskRetrieval(statements: [], statementRoutes: [], passages: [])

    var isEmpty: Bool { statements.isEmpty && passages.isEmpty }
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
                guard !seen.contains(key), !entry.formattedBody.isEmpty else { continue }
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

        var passages: [String] = []
        if let documentIndex, passageLimit > 0 {
            passages = documentIndex.passages(
                matching: query,
                queryVector: queryVector,
                limit: passageLimit,
                excludingPage: pageIndex
            )
        }

        // A passage that substantially repeats an injected statement wastes budget.
        let statementBodies = collected.map { collapseWhitespace($0.entry.formattedBody) }
        passages = passages.filter { passage in
            let normalized = collapseWhitespace(passage)
            return !statementBodies.contains { body in
                let probe = String(body.prefix(80))
                return probe.count >= 40 && normalized.contains(probe)
            }
        }

        return AskRetrieval(
            statements: collected.map { "\($0.entry.promptHeading):\n\($0.entry.formattedBody)" },
            statementRoutes: collected.map(\.route),
            passages: passages
        )
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
