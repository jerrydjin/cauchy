import Foundation
import FoundationModels

enum ReadingAssistantAvailability: Equatable {
    case available(AssistantConnectorID)
    case deviceNotEligible
    case intelligenceNotEnabled
    case modelNotReady
    case apiKeyMissing(CloudAPIProvider)
    case cliNotInstalled(AssistantConnectorID)
    case unavailable
}

extension ReadingAssistantAvailability {
    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var activeProvider: AssistantConnectorID? {
        if case .available(let provider) = self { return provider }
        return nil
    }
}

@MainActor
protocol ReadingAssistantProtocol: AnyObject {
    var provider: AssistantConnectorID { get }
    var availability: ReadingAssistantAvailability { get }
    var isResponding: Bool { get }
    func resetSession(context: ReadingContext)
    func restoreSession(context: ReadingContext, messages: [ThreadMessage])
    /// `retrieval` (exact statements + passages) reaches the model's prompt but
    /// is never stored in thread history or shown in the chat UI.
    func ask(question: String, retrieval: AskRetrieval, onPartial: ((String) -> Void)?) async throws -> String
}

extension ReadingAssistantProtocol {
    func ask(question: String, onPartial: ((String) -> Void)? = nil) async throws -> String {
        try await ask(question: question, retrieval: .empty, onPartial: onPartial)
    }
}

enum ReadingAssistantError: LocalizedError {
    case notAvailable(ReadingAssistantAvailability)
    case sessionUnavailable
    case sessionBusy
    case languageModel(LanguageModelError)
    case invalidAPIKey(CloudAPIProvider)
    case rateLimited(CloudAPIProvider)
    case network(String)
    case api(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable(let availability):
            switch availability {
            case .available:
                return nil
            case .deviceNotEligible:
                return "This Mac is not eligible for Apple Intelligence."
            case .intelligenceNotEnabled:
                return "Turn on Apple Intelligence in System Settings to use Ask."
            case .modelNotReady:
                return "The on-device model is still downloading. Try again shortly."
            case .apiKeyMissing(let provider):
                return "Add your \(provider.vendor) API key in Settings to use Ask."
            case .cliNotInstalled(let provider):
                return "\(provider.connector.name) is not set up. \(provider.connector.setupHint)"
            case .unavailable:
                return "Ask is not available right now."
            }
        case .sessionUnavailable:
            return "Could not start a reading assistant session."
        case .sessionBusy:
            return "The assistant is still responding. Wait for the current answer to finish."
        case .languageModel(let error):
            if case .contextSizeExceeded = error {
                return "The selected passage is too long for the model context window. Try selecting a shorter excerpt."
            }
            return error.localizedDescription
        case .invalidAPIKey(let provider):
            return "The \(provider.vendor) API key is invalid. Check your key in Settings."
        case .rateLimited(let provider):
            return "\(provider.vendor) rate limit reached. Try again in a moment."
        case .network(let message):
            return "Network error: \(message)"
        case .api(let message):
            return message
        }
    }
}
