import Foundation

/// The optional highlight tag above the ask box. Absent means the question is
/// about the whole open document.
struct AskHighlightFocus: Equatable, Sendable {
    var pageIndex: Int
    var excerpt: String
    var surroundingText: String
    var fingerprint: String
    var bounds: NormalizedRect?
    var lines: [HighlightLine]?
    var highlightID: UUID?

    var tagTitle: String {
        let flat = excerpt
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let clipped = flat.count > 42 ? String(flat.prefix(42)) + "…" : flat
        if clipped.isEmpty {
            return "Page \(pageIndex + 1)"
        }
        return "p. \(pageIndex + 1) · \(clipped)"
    }
}

/// A problem sheet the reader dropped on the ask box. `extractedText` is the
/// PDFKit text layer, or Vision text recognition for an image.
struct AskProblemSheet: Equatable, Sendable, Identifiable {
    var id: UUID
    var fileName: String
    var extractedText: String

    var tagTitle: String { fileName }

    init(id: UUID = UUID(), fileName: String, extractedText: String) {
        self.id = id
        self.fileName = fileName
        self.extractedText = extractedText
    }
}

/// What one ask is about. `nil` scope is resolved by the caller from the
/// active thread; the prompt builder always receives an explicit scope.
enum AskScope: Equatable, Sendable {
    case wholeDocument
    case highlight(AskHighlightFocus)

    var highlight: AskHighlightFocus? {
        if case .highlight(let focus) = self { return focus }
        return nil
    }

    var pageIndex: Int? {
        highlight?.pageIndex
    }
}

/// Builds the session instructions and the per-turn preface for Ask.
///
/// The on-device Foundation Models window is about 4,096 tokens, shared with
/// these instructions, the retrieved excerpts, and the generated answer.
/// Character budgets below are sized so a whole-document question still fits
/// that window: statements and passages keep the limits in
/// `ReadingPromptBuilder.evidenceBudgets`, and the sheet plus earlier turns
/// are clipped here rather than sending the PDF.
enum AskPromptBuilder {
    /// ~4,096 tokens on device. These caps leave room for instructions,
    /// retrieved statements (1,200), passages (800), and the reply.
    static let onDeviceHistoryCharacters = 1_200
    static let extendedHistoryCharacters = 12_000
    static let onDeviceSheetCharacters = 900
    static let extendedSheetCharacters = 6_000
    /// Stored sheet text. The per-provider cap above is applied again at ask time.
    static let storedSheetCharacters = 20_000

    static func historyCharacterBudget(for provider: AssistantConnectorID) -> Int {
        provider == .onDevice ? onDeviceHistoryCharacters : extendedHistoryCharacters
    }

    static func sheetCharacterBudget(for provider: AssistantConnectorID) -> Int {
        provider == .onDevice ? onDeviceSheetCharacters : extendedSheetCharacters
    }

    /// Most recent turns that fit the provider, dropped from the front so a
    /// follow-up still sees the latest question and answer.
    static func trimmedHistory(_ messages: [ThreadMessage], provider: AssistantConnectorID) -> [ThreadMessage] {
        let budget = historyCharacterBudget(for: provider)
        guard budget > 0, !messages.isEmpty else { return [] }

        var total = 0
        var kept: [ThreadMessage] = []
        for message in messages.reversed() {
            let cost = message.content.count
            if total + cost > budget {
                if kept.isEmpty, cost > 0 {
                    var clipped = message
                    clipped.content = String(message.content.suffix(budget))
                    kept.append(clipped)
                }
                break
            }
            total += cost
            kept.append(message)
        }
        return Array(kept.reversed())
    }

    static func sessionContext(documentTitle: String, scope: AskScope) -> ReadingContext {
        switch scope {
        case .wholeDocument:
            return ReadingContext(
                documentTitle: documentTitle,
                selectedText: "",
                surroundingText: "",
                retrievedPassages: []
            )
        case .highlight(let focus):
            return ReadingContext(
                documentTitle: documentTitle,
                selectedText: focus.excerpt,
                surroundingText: focus.surroundingText,
                retrievedPassages: []
            )
        }
    }

    static func sessionInstructions(
        documentTitle: String,
        scope: AskScope,
        provider: AssistantConnectorID
    ) -> String {
        switch scope {
        case .wholeDocument:
            return ReadingPromptBuilder.instructions(
                for: ReadingContext(
                    documentTitle: documentTitle,
                    selectedText: "",
                    surroundingText: "",
                    retrievedPassages: []
                ),
                provider: provider
            )
        case .highlight(let focus):
            return ReadingPromptBuilder.instructions(
                for: ReadingContext(
                    documentTitle: documentTitle,
                    selectedText: focus.excerpt,
                    surroundingText: focus.surroundingText,
                    retrievedPassages: []
                ),
                provider: provider
            )
        }
    }

    /// Preface for this turn only. It is not written into thread history.
    /// Highlight text lives in the session instructions; the sheet is here
    /// because it changes from question to question.
    static func turnPreface(
        scope: AskScope,
        sheet: AskProblemSheet?,
        provider: AssistantConnectorID
    ) -> String {
        var parts: [String] = [fullAnswerInstruction, citationInstruction]

        switch scope {
        case .wholeDocument:
            parts.append("SCOPE: No passage is highlighted. Answer about the whole open document, using the supplied excerpts rather than reciting the PDF.")
        case .highlight(let focus):
            parts.append("SCOPE: A passage is highlighted on PDF page \(focus.pageIndex + 1). Answer about that passage first.")
        }

        if let sheet, !sheet.extractedText.isEmpty {
            let text = clippedSheetText(sheet.extractedText, provider: provider)
            parts.append(
                """
                ATTACHED PROBLEM SHEET (\(sheet.fileName)):
                The reader attached this sheet. Treat its text as the question they are asking about. Extraction can lose mathematical layout; do not invent symbols that are not written here.
                ---
                \(text)
                ---
                """
            )
        }

        return parts.joined(separator: "\n\n")
    }

    /// Prior turns for this follow-up, already trimmed to the provider budget.
    /// Empty when this is the first question. Not stored again inside the thread.
    static func priorConversation(_ messages: [ThreadMessage], provider: AssistantConnectorID) -> String? {
        let kept = trimmedHistory(messages, provider: provider)
        guard !kept.isEmpty else { return nil }
        var lines = ["EARLIER CONVERSATION:"]
        for message in kept {
            let speaker = message.role == .user ? "User" : "Assistant"
            lines.append("\(speaker): \(message.content)")
        }
        lines.append("Answer the new question. Use the earlier turns as context, and do not repeat them unless the reader asks.")
        return lines.joined(separator: "\n")
    }

    static func clippedSheetText(_ text: String, provider: AssistantConnectorID) -> String {
        let budget = sheetCharacterBudget(for: provider)
        guard text.count > budget else { return text }
        return String(text.prefix(budget))
    }

    /// Session instructions plus the per-turn preface and the reader's question.
    /// Tests assert on this; assistants send the two halves separately (the
    /// session holds the instructions, the turn holds the preface).
    static func modelPrompt(
        documentTitle: String,
        question: String,
        scope: AskScope,
        sheet: AskProblemSheet?,
        history: [ThreadMessage] = [],
        provider: AssistantConnectorID
    ) -> String {
        let instructions = sessionInstructions(documentTitle: documentTitle, scope: scope, provider: provider)
        let preface = turnPreface(scope: scope, sheet: sheet, provider: provider)
        var parts = [instructions, preface]
        if let earlier = priorConversation(history, provider: provider) {
            parts.append(earlier)
        }
        return parts.joined(separator: "\n\n") + "\n\nQUESTION: " + question
    }

    private static let fullAnswerInstruction = """
    RESPONSE STYLE: Give the full answer. Work through the question, and cite this document's own results at the steps that use them.
    """

    private static let citationInstruction = """
    CITATIONS: Ground the answer in this document's own numbered results. Cite them in the form "by Theorem 3.2" or "Lemma 2.1", and only when that result appears in the supplied PDF source excerpts. Do not invent a number.
    """
}
