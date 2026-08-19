import Foundation
import Observation

@MainActor
@Observable
final class SelectionThreadViewModel {
    var activeThread: SelectionThread?
    var isResponding = false

    private var assistant: any ReadingAssistantProtocol
    /// Injected by WorkspaceViewModel once the background build finishes; nil
    /// until then (asks simply run without retrieved passages).
    var documentIndex: (any DocumentIndexProtocol)?
    /// The workspace's reference index — exact statements of numbered
    /// definitions/theorems, injected into asks as ground truth. Wired once by
    /// WorkspaceViewModel (the same instance is cleared/refilled per document).
    var referenceIndex: DocumentReferenceIndex?

    init(assistant: any ReadingAssistantProtocol = ReadingAssistantFactory.makeAssistant()) {
        self.assistant = assistant
    }

    var hasSelection: Bool {
        activeThread != nil && !(activeThread?.selectedText.isEmpty ?? true)
    }

    /// Swaps in the newly selected provider. The active thread's session is
    /// restored onto the new assistant so a mid-thread provider change keeps
    /// the passage context instead of falling back to a generic prompt.
    func reloadAssistant(documentTitle: String? = nil) {
        assistant = ReadingAssistantFactory.makeAssistant()
        guard let thread = activeThread, let documentTitle else { return }
        let readingContext = ReadingContextBuilder.from(
            anchor: thread.anchor,
            documentTitle: documentTitle,
            index: documentIndex
        )
        assistant.restoreSession(context: readingContext, messages: thread.messages)
    }

    func updateSelection(
        _ context: TextSelectionContext?,
        documentTitle: String,
        existingHighlights: [Highlight]
    ) {
        guard let context, !context.selectedText.isEmpty else {
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
        onPersist: (SelectionThread) -> Void
    ) async throws {
        guard var thread = activeThread else { return }
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        thread.messages.append(ThreadMessage(role: .user, content: trimmed))
        thread.streamingAssistantText = ""
        activeThread = thread

        let coalescer = StreamingTextCoalescer()
        coalescer.onFlush = { [weak self] partial in
            self?.activeThread?.streamingAssistantText = partial
        }

        isResponding = true
        defer {
            coalescer.cancel()
            isResponding = false
            activeThread?.streamingAssistantText = nil
        }

        // Retrieval happens now — at ask time — because the query needs the
        // question; the session context predates it.
        let retrieval = retrieveContext(question: trimmed, thread: thread)

        // onPartial already runs on the main actor (ReadingAssistantProtocol is
        // @MainActor); the coalescer keeps re-renders at ~12/s instead of per token.
        let assistantText = try await assistant.ask(question: trimmed, retrieval: retrieval) { partial in
            coalescer.submit(partial)
        }

        thread.messages.append(ThreadMessage(role: .assistant, content: assistantText))
        thread.isPersisted = true
        activeThread = thread
        onPersist(thread)
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
        activeThread = thread
        return last.content
    }

    private func retrieveContext(question: String, thread: SelectionThread) -> AskRetrieval {
        AskContextRetriever.retrieve(
            question: question,
            selectedText: thread.selectedText,
            surroundingText: thread.surroundingText,
            pageIndex: thread.pageIndex,
            referenceIndex: referenceIndex,
            documentIndex: documentIndex,
            // The on-device window is small; cloud/CLI providers can take more.
            passageLimit: assistant.provider == .onDevice ? 3 : 5
        )
    }
}
