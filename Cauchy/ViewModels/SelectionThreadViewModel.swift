import Foundation
import Observation

@MainActor
@Observable
final class SelectionThreadViewModel {
    var activeThread: SelectionThread?
    var isResponding = false

    private var assistant: any ReadingAssistantProtocol
    private let documentIndex: DocumentIndexProtocol = DocumentIndex()

    init(assistant: any ReadingAssistantProtocol = ReadingAssistantProviderFactory.makeAssistant()) {
        self.assistant = assistant
    }

    var hasSelection: Bool {
        activeThread != nil && !(activeThread?.selectedText.isEmpty ?? true)
    }

    func reloadAssistant() {
        assistant = ReadingAssistantProviderFactory.makeAssistant()
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

        isResponding = true
        defer {
            isResponding = false
            activeThread?.streamingAssistantText = nil
        }

        let assistantText = try await assistant.ask(question: trimmed) { [weak self] partial in
            Task { @MainActor in
                self?.activeThread?.streamingAssistantText = partial
            }
        }

        thread.messages.append(ThreadMessage(role: .assistant, content: assistantText))
        thread.isPersisted = true
        activeThread = thread
        onPersist(thread)
    }

    func currentMessagesForSave() -> [ThreadMessage] {
        activeThread?.messages ?? []
    }
}
