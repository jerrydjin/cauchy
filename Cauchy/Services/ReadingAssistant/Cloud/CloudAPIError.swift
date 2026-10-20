import Foundation

/// A failure from a BYOK provider's HTTP API. Carries the provider so the
/// message can name the vendor whose key or quota is the problem.
enum CloudAPIError: LocalizedError, Sendable {
    case invalidAPIKey(CloudAPIProvider)
    case modelUnavailable(CloudAPIProvider, String)
    case rateLimited(CloudAPIProvider)
    case network(String)
    case api(String)

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey(let provider):
            return "The \(provider.vendor) API key is invalid."
        case .modelUnavailable(let provider, let message):
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "That model isn't available on \(provider.vendor)." : detail
        case .rateLimited(let provider):
            return "\(provider.vendor) rate limit reached."
        case .network(let message):
            return "Network error: \(message)"
        case .api(let message):
            return message
        }
    }
}
