import Foundation

/// Stand-in used when Apple Intelligence cannot run and nothing else is
/// configured. Ask stays on screen; sending reports that a provider is needed.
@MainActor
final class UnconfiguredReadingAssistant: ReadingAssistantProtocol {
    let provider: AssistantConnectorID = .onDevice
    var availability: ReadingAssistantAvailability { .chooseProvider }
    var isResponding: Bool { false }

    func resetSession(context: ReadingContext) {}

    func restoreSession(context: ReadingContext, messages: [ThreadMessage]) {}

    func ask(
        question: String,
        retrieval: AskRetrieval,
        onPartial: ((String) -> Void)? = nil
    ) async throws -> String {
        throw ReadingAssistantError.notAvailable(.chooseProvider)
    }
}
