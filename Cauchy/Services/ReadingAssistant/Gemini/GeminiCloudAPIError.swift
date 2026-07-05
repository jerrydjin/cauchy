import Foundation

enum GeminiCloudAPIError: LocalizedError, Sendable {
    case invalidAPIKey
    case rateLimited
    case network(String)
    case api(String)

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "The Gemini API key is invalid."
        case .rateLimited:
            return "Gemini rate limit reached."
        case .network(let message):
            return "Network error: \(message)"
        case .api(let message):
            return message
        }
    }
}
