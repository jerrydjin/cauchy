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

    init(assistant: any ReadingAssistantProtocol = ReadingAssistantProviderFactory.makeAssistant()) {
        self.assistant = assistant
    }

    var hasSelection: Bool {
        activeThread != nil && !(activeThread?.selectedText.isEmpty ?? true)
    }

    /// Swaps in the newly selected provider. The active thread's session is
    /// restored onto the new assistant so a mid-thread provider change keeps
    /// the passage context instead of falling back to a generic prompt.
    func reloadAssistant(documentTitle: String? = nil) {
        assistant = ReadingAssistantProviderFactory.makeAssistant()
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
            activeThread?.lineBounds = context.lineBounds
            return
        }

        if let existing = existingHighlights.first(where: {
            $0.pageIndex == context.pageIndex && $0.selectedText == context.selectedText
        }) {
            restoreThread(from: existing, documentTitle: documentTitle)
            activeThread?.bounds = context.bounds ?? existing.bounds
            activeThread?.lineBounds = context.lineBounds ?? existing.lineBounds
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
            lineBounds: context.lineBounds,
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
            lineBounds: highlight.lineBounds,
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
        let passages = retrievePassages(question: trimmed, thread: thread)

        // onPartial already runs on the main actor (ReadingAssistantProtocol is
        // @MainActor); the coalescer keeps re-renders at ~12/s instead of per token.
        let assistantText = try await assistant.ask(question: trimmed, retrievedPassages: passages) { partial in
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

    private func retrievePassages(question: String, thread: SelectionThread) -> [String] {
        guard let documentIndex else { return [] }
        let query = question + " " + thread.selectedText.prefix(200)
        return documentIndex.passages(matching: query, limit: 3, excludingPage: thread.pageIndex)
    }
}
