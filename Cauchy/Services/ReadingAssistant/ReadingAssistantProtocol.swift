import Foundation
import FoundationModels

enum ReadingAssistantProvider: Equatable, Sendable {
    case local
    case gemini
    case claudeCode
    case codex

    var cliDisplayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .local, .gemini: ""
        }
    }
}

enum ReadingAssistantAvailability: Equatable {
    case available(ReadingAssistantProvider)
    case deviceNotEligible
    case intelligenceNotEnabled
    case modelNotReady
    case geminiKeyMissing
    case cliNotInstalled(ReadingAssistantProvider)
    case unavailable
}

extension ReadingAssistantAvailability {
    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var activeProvider: ReadingAssistantProvider? {
        if case .available(let provider) = self { return provider }
        return nil
    }
}

@MainActor
protocol ReadingAssistantProtocol: AnyObject {
    var provider: ReadingAssistantProvider { get }
    var availability: ReadingAssistantAvailability { get }
    var isResponding: Bool { get }
    func resetSession(context: ReadingContext)
    func restoreSession(context: ReadingContext, messages: [ThreadMessage])
    func ask(question: String, onPartial: ((String) -> Void)?) async throws -> String
}

enum ReadingAssistantError: LocalizedError {
    case notAvailable(ReadingAssistantAvailability)
    case sessionUnavailable
    case sessionBusy
    case languageModel(LanguageModelError)
    case invalidAPIKey
    case rateLimited
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
            case .geminiKeyMissing:
                return "Add a Gemini API key in Settings to use Ask."
            case .cliNotInstalled(let provider):
                return "\(provider.cliDisplayName) is not installed. Install its CLI and sign in, then try again."
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
        case .invalidAPIKey:
            return "The Gemini API key is invalid. Check your key in Settings."
        case .rateLimited:
            return "Gemini rate limit reached. Try again in a moment."
        case .network(let message):
            return "Network error: \(message)"
        case .api(let message):
            return message
        }
    }
}
