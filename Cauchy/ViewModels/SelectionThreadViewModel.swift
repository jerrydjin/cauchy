import Foundation
import Observation
import PDFKit

@MainActor
@Observable
final class SelectionThreadViewModel {
    var activeThread: SelectionThread?
    var isResponding = false

    /// Built on first use, not at init. Making one reads the user's connector
    /// choice and, for a BYOK provider, their Keychain — and a workspace is
    /// constructed while its window is being put on screen, so doing it eagerly
    /// blocks the first window behind a Keychain call (and, when the binary's
    /// signature has changed, behind an authorization prompt).
    private var loadedAssistant: (any ReadingAssistantProtocol)?

    private var assistant: any ReadingAssistantProtocol {
        if let loadedAssistant { return loadedAssistant }
        let made = ReadingAssistantFactory.makeAssistant()
        loadedAssistant = made
        return made
    }
    /// Injected by WorkspaceViewModel once the background build finishes; nil
    /// until then (asks simply run without retrieved passages).
    var documentIndex: (any DocumentIndexProtocol)?
    /// The workspace's reference index — exact statements of numbered
    /// definitions/theorems, injected into asks as ground truth. Wired once by
    /// WorkspaceViewModel (the same instance is cleared/refilled per document).
    var referenceIndex: DocumentReferenceIndex?
    /// The current document is used only to revalidate exact source locations
    /// before they are saved with a reply.
    var pdfDocument: PDFDocument?

    /// Conversation that is not tied to a highlight. Questions with no tag
    /// land here, and it survives switching over to a highlight thread.
    private(set) var documentThread = SelectionThread(
        anchorID: UUID(),
        pageIndex: 0,
        selectedText: "",
        surroundingText: "",
        messages: [],
        isPersisted: true
    )

    var documentConversationID: UUID { documentThread.anchorID }

    var isDocumentConversation: Bool {
        activeThread?.anchorID == documentThread.anchorID
    }

    /// `assistant` is for tests and previews; production leaves it nil so the
    /// real one is made the first time it is actually needed.
    init(assistant: (any ReadingAssistantProtocol)? = nil) {
        self.loadedAssistant = assistant
    }

    var hasSelection: Bool {
        activeThread != nil && !(activeThread?.selectedText.isEmpty ?? true)
    }

    /// Swaps in the newly selected provider. The active thread's session is
    /// restored onto the new assistant so a mid-thread provider change keeps
    /// the passage context instead of falling back to a generic prompt.
    func reloadAssistant(documentTitle: String? = nil) {
        loadedAssistant = ReadingAssistantFactory.makeAssistant()
        guard let thread = activeThread, let documentTitle else { return }
        let scope = scope(for: thread)
        let readingContext = AskPromptBuilder.sessionContext(documentTitle: documentTitle, scope: scope)
        assistant.restoreSession(
            context: readingContext,
            messages: AskPromptBuilder.trimmedHistory(thread.messages, provider: assistant.provider)
        )
    }

    func loadDocumentConversation(id: UUID, messages: [ThreadMessage]) {
        documentThread = SelectionThread(
            anchorID: id,
            pageIndex: 0,
            selectedText: "",
            surroundingText: "",
            messages: messages,
            isPersisted: true
        )
    }

    /// Whole-document chat. Does not clear a highlight thread the reader may
    /// switch back to; that thread lives on the highlight.
    func activateDocumentConversation(documentTitle: String) {
        activeThread = documentThread
        let context = AskPromptBuilder.sessionContext(documentTitle: documentTitle, scope: .wholeDocument)
        assistant.restoreSession(
            context: context,
            messages: AskPromptBuilder.trimmedHistory(documentThread.messages, provider: assistant.provider)
        )
    }

    /// Drops the visible conversation's messages and starts the assistant fresh.
    /// The highlight passage, when there is one, stays.
    func startNewConversation(documentTitle: String) {
        guard var thread = activeThread else {
            activateDocumentConversation(documentTitle: documentTitle)
            return
        }
        thread.messages = []
        thread.streamingAssistantText = nil
        commit(thread)
        let scope = scope(for: thread)
        assistant.resetSession(context: AskPromptBuilder.sessionContext(documentTitle: documentTitle, scope: scope))
    }

    func updateSelection(
        _ context: TextSelectionContext?,
        documentTitle: String,
        existingHighlights: [Highlight]
    ) {
        guard let context, !context.selectedText.isEmpty else {
            // Clearing the PDF selection must not throw away the document chat.
            if activeThread?.anchorID == documentThread.anchorID {
                return
            }
            activeThread = nil
            return
        }

        if let current = activeThread,
           current.pageIndex == context.pageIndex && current.selectedText == context.selectedText {
            activeThread?.selectedText = context.selectedText
            activeThread?.surroundingText = context.surroundingText
            activeThread?.bounds = context.bounds
            activeThread?.lines = context.lines
            return
        }

        if let existing = existingHighlights.first(where: {
            $0.pageIndex == context.pageIndex && $0.selectedText == context.selectedText
        }) {
            restoreThread(from: existing, documentTitle: documentTitle)
            activeThread?.bounds = context.bounds ?? existing.bounds
            activeThread?.lines = context.lines ?? existing.lines
            activeThread?.surroundingText = context.surroundingText
            return
        }

        let anchorID = UUID()
        activeThread = SelectionThread(
            anchorID: anchorID,
            pageIndex: context.pageIndex,
            selectedText: context.selectedText,
            surroundingText: context.surroundingText,
            bounds: context.bounds,
            lines: context.lines,
            messages: [],
            isPersisted: false
        )

        let readingContext = ReadingContextBuilder.from(
            anchor: activeThread!.anchor,
            documentTitle: documentTitle,
            index: documentIndex
        )
        assistant.resetSession(context: readingContext)
    }

    func restoreThread(from highlight: Highlight, documentTitle: String) {
        activeThread = SelectionThread(
            anchorID: highlight.id,
            pageIndex: highlight.pageIndex,
            selectedText: highlight.selectedText,
            surroundingText: highlight.surroundingText,
            bounds: highlight.bounds,
            lines: highlight.lines,
            messages: highlight.messages,
            isPersisted: true
        )

        let readingContext = ReadingContextBuilder.from(
            anchor: highlight.anchor,
            documentTitle: documentTitle,
            index: documentIndex
        )
        assistant.restoreSession(context: readingContext, messages: highlight.messages)
    }

    func sendMessage(
        _ question: String,
        documentTitle: String,
        scope explicitScope: AskScope? = nil,
        sheet: AskProblemSheet? = nil,
        onPersist: (SelectionThread) -> Void
    ) async throws {
        guard var thread = activeThread else { return }
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let scope = explicitScope ?? scope(for: thread)

        thread.messages.append(ThreadMessage(role: .user, content: trimmed))
        thread.streamingAssistantText = ""
        thread.failureNotice = nil
        commit(thread)

        // Freeze answer provenance before the async call. A model-picker
        // change while tokens are streaming must not relabel this reply as if
        // the newly selected connector had produced it.
        let answeringAssistant = assistant
        let answerProvider = answeringAssistant.provider
        let answerModelID: String? = switch AssistantPreferences.modelChoice(for: answerProvider) {
        case .model(let id): id
        case .connectorDefault: nil
        }

        let coalescer = StreamingTextCoalescer()
        coalescer.onFlush = { [weak self] partial in
            self?.activeThread?.streamingAssistantText = AssistantAnswerBoundary.displayContent(partial)
        }

        isResponding = true
        defer {
            coalescer.cancel()
            isResponding = false
            activeThread?.streamingAssistantText = nil
        }

        let prior = Array(thread.messages.dropLast())
        // Instructions only. The trimmed turns ride `priorConversation` so
        // Foundation Models, the cloud API, and the CLI agent all see the same
        // follow-up context, once, inside the provider's character budget.
        answeringAssistant.restoreSession(
            context: AskPromptBuilder.sessionContext(documentTitle: documentTitle, scope: scope),
            messages: []
        )

        // Retrieval happens now — at ask time — because the query needs the
        // question; the session context predates it. The sheet's text is part
        // of the query so a theorem it names is retrieved from the notes.
        let sheetText = sheet.map { AskPromptBuilder.clippedSheetText($0.extractedText, provider: answerProvider) } ?? ""
        let retrievalQuestion = [trimmed, sheetText].filter { !$0.isEmpty }.joined(separator: "\n")
        var retrieval = retrieveContext(
            question: retrievalQuestion,
            asked: trimmed,
            scope: scope,
            provider: answerProvider
        ).clippedForPrompt(provider: answerProvider)
        if let miss = retrieval.structureMissMessage, scope.highlight == nil {
            thread.messages.append(ThreadMessage(
                role: .assistant,
                content: miss,
                answerEvidence: AnswerEvidence(
                    basis: .insufficient,
                    sourcePages: [],
                    referencedStatementCount: 0,
                    retrievedPassageCount: 0,
                    providerID: answerProvider.rawValue,
                    modelID: answerModelID,
                    sourceAnchors: [],
                    citationStatus: nil,
                    citedSourceIDs: [],
                    declaredBasis: .insufficient
                )
            ))
            thread.streamingAssistantText = nil
            commit(thread)
            onPersist(thread)
            return
        }
        let sourceAnchors = resolvedSourceAnchors(thread: thread, scope: scope, retrieval: retrieval)
        retrieval.citableSources = sourceAnchors
        var preface = AskPromptBuilder.turnPreface(
            scope: scope,
            sheet: sheet,
            provider: answerProvider
        )
        if let note = retrieval.structureNote {
            preface += "\n\n" + note
        }
        retrieval.turnPreface = preface
        retrieval.priorConversation = AskPromptBuilder.priorConversation(prior, provider: answerProvider)

        // onPartial already runs on the main actor (ReadingAssistantProtocol is
        // @MainActor); the coalescer keeps re-renders at ~12/s instead of per token.
        let assistantText = try await answeringAssistant.ask(question: trimmed, retrieval: retrieval) { partial in
            coalescer.submit(partial)
        }
        let parsed = AssistantAnswerBoundary.parse(assistantText)
        let citationAudit = AnswerCitationAudit.evaluate(parsed.content, sources: sourceAnchors)
        let acceptedBasis: AnswerBasis = parsed.basis == .pdf && citationAudit.status != .idsResolve
            ? .unverified : parsed.basis
        let selectionPages = scope.highlight == nil ? [] : [thread.pageIndex + 1]
        let pages = Array(Set(selectionPages + retrieval.sourcePageNumbers)).sorted()
        let evidence = AnswerEvidence(
            basis: acceptedBasis,
            sourcePages: pages,
            referencedStatementCount: retrieval.statements.count,
            retrievedPassageCount: retrieval.passages.count,
            providerID: answerProvider.rawValue,
            modelID: answerModelID,
            sourceAnchors: sourceAnchors,
            citationStatus: citationAudit.status,
            citedSourceIDs: citationAudit.citedSourceIDs,
            declaredBasis: parsed.basis
        )
        thread.messages.append(ThreadMessage(
            role: .assistant,
            content: parsed.content,
            answerEvidence: evidence
        ))
        if thread.anchorID != documentThread.anchorID {
            thread.isPersisted = true
        }
        thread.streamingAssistantText = nil
        thread.failureNotice = nil
        commit(thread)
        ProviderReadinessStore.shared.markReady(connectorID: answerProvider, modelID: answerModelID)
        onPersist(thread)
    }

    func noteFailure(_ message: String) {
        guard var thread = activeThread else { return }
        thread.failureNotice = message
        thread.streamingAssistantText = nil
        commit(thread)
    }

    func currentMessagesForSave() -> [ThreadMessage] {
        activeThread?.messages ?? []
    }

    /// Pops the trailing user message when an ask was stopped before it was
    /// answered, and returns its text so the composer can offer it back.
    /// Providers only record a turn once it completes, so leaving the orphan
    /// visible would show history the model will never see.
    func discardUnansweredQuestion() -> String? {
        guard var thread = activeThread,
              let last = thread.messages.last,
              last.role == .user else { return nil }
        thread.messages.removeLast()
        commit(thread)
        return last.content
    }

    private func scope(for thread: SelectionThread) -> AskScope {
        let excerpt = thread.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !excerpt.isEmpty else { return .wholeDocument }
        return .highlight(AskHighlightFocus(
            pageIndex: thread.pageIndex,
            excerpt: thread.selectedText,
            surroundingText: thread.surroundingText,
            fingerprint: "",
            bounds: thread.bounds,
            lines: thread.lines,
            highlightID: thread.isPersisted ? thread.anchorID : nil
        ))
    }

    private func commit(_ thread: SelectionThread) {
        activeThread = thread
        if thread.anchorID == documentThread.anchorID {
            documentThread = thread
        }
    }

    private func retrieveContext(
        question: String,
        asked: String,
        scope: AskScope,
        provider: AssistantConnectorID
    ) -> AskRetrieval {
        let focus = scope.highlight
        let budgets = ReadingPromptBuilder.evidenceBudgets(for: provider)
        let structuralQuery = AskStructureLocator.query(in: asked)
        let structure = structuralQuery.flatMap { _ in pdfDocument.map { AskStructureLocator.structure(from: $0) } }
        return AskContextRetriever.retrieve(
            question: question,
            selectedText: focus?.excerpt ?? "",
            surroundingText: focus?.surroundingText ?? "",
            pageIndex: scope.pageIndex,
            referenceIndex: referenceIndex,
            documentIndex: documentIndex,
            // The on-device window is small; cloud/CLI providers can take more.
            passageLimit: provider == .onDevice ? 3 : 5,
            structuralQuery: structuralQuery,
            structure: structure,
            passageCharacterBudget: budgets.passages
        )
    }

    private func resolvedSourceAnchors(
        thread: SelectionThread,
        scope: AskScope,
        retrieval: AskRetrieval
    ) -> [AnswerSourceAnchor] {
        guard let document = pdfDocument else { return [] }
        var anchors: [AnswerSourceAnchor] = []
        if scope.highlight != nil,
           let page = document.page(at: thread.pageIndex),
           let pageText = page.string,
           let source = LexicalDocumentIndex.sourceLocation(
               for: thread.selectedText,
               in: pageText,
               pageIndex: thread.pageIndex,
               after: 0
           ),
           let region = ReferenceEvidenceRegionResolver.exactRegion(
               matchedText: source.matchedText,
               startOffset: source.startOffset,
               endOffset: source.endOffset,
               on: page
           ) {
            anchors.append(AnswerSourceAnchor(
                label: "Selected passage",
                pageIndex: thread.pageIndex,
                region: region,
                sourceID: "S1"
            ))
        }
        for (index, entry) in retrieval.statementReferences.enumerated() {
            guard let source = entry.evidence,
                  source.effectiveSource == .pdfText,
                  let page = document.page(at: entry.pageIndex),
                  let region = ReferenceEvidenceRegionResolver.exactRegion(for: source, on: page)
            else { continue }
            anchors.append(AnswerSourceAnchor(
                label: AskStructureLocator.statementLabel(entry),
                pageIndex: entry.pageIndex,
                region: region,
                sourceID: "R\(index + 1)"
            ))
        }
        let outlineHeadings = AskStructureLocator.outlineHeadings(in: document)
        for (index, record) in retrieval.passageRecords.enumerated() {
            guard let source = record.location,
                  let page = document.page(at: source.pageIndex),
                  let region = ReferenceEvidenceRegionResolver.exactRegion(
                      matchedText: source.matchedText,
                      startOffset: source.startOffset,
                      endOffset: source.endOffset,
                      on: page
                  ) else { continue }
            anchors.append(AnswerSourceAnchor(
                label: passageLabel(
                    record: record,
                    pageIndex: source.pageIndex,
                    statements: retrieval.statementReferences,
                    headings: outlineHeadings
                ),
                pageIndex: source.pageIndex,
                region: region,
                sourceID: "P\(index + 1)"
            ))
        }
        return anchors
    }

    private func passageLabel(
        record: DocumentPassage,
        pageIndex: Int,
        statements: [IndexedReference],
        headings: [AskHeading]
    ) -> String {
        if let label = record.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            return label
        }
        if let named = statements.first(where: {
            $0.pageIndex == pageIndex && record.text.localizedCaseInsensitiveContains($0.reference.displayName)
        }) {
            return AskStructureLocator.statementLabel(named)
        }
        if let onPage = statements.first(where: { $0.pageIndex == pageIndex }) {
            return AskStructureLocator.statementLabel(onPage)
        }
        if let heading = AskStructureLocator.nearestHeading(onOrBefore: pageIndex, in: headings) {
            return heading
        }
        return "p. \(pageIndex + 1)"
    }

}
