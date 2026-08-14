import Foundation

/// A cloud vendor the user reaches with a key of their own — the "bring your
/// own key" half of the connector list, as opposed to the CLIs that ride a
/// subscription the user already pays for.
///
/// Everything that differs between vendors hangs off this one enum: where the
/// key lives in the Keychain, where the user gets one, and which wire format
/// the API speaks. Adding a fourth vendor is a case here plus a
/// `CloudWireFormat` — no call site outside those two knows the difference.
enum CloudAPIProvider: String, CaseIterable, Identifiable, Hashable, Sendable {
    case anthropic
    case openai
    /// Raw value stays `gemini`: the connector id, the stored model choice and
    /// the Keychain item all predate BYOK and must keep working.
    case gemini

    var id: String { rawValue }

    var name: String {
        switch self {
        case .anthropic: "Anthropic API"
        case .openai: "OpenAI API"
        case .gemini: "Gemini API"
        }
    }

    /// Who bills the key, for the Settings row.
    var vendor: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openai: "OpenAI"
        case .gemini: "Google"
        }
    }

    var symbol: String {
        switch self {
        case .anthropic: "asterisk"
        case .openai: "circle.hexagongrid"
        case .gemini: "sparkle"
        }
    }

    /// Shown as the secure field's placeholder — a key pasted from the wrong
    /// console is the likeliest mistake, and the prefix catches it on sight.
    var keyPrefixHint: String {
        switch self {
        case .anthropic: "sk-ant-…"
        case .openai: "sk-…"
        case .gemini: "AIza…"
        }
    }

    var consoleURL: URL {
        switch self {
        case .anthropic: URL(string: "https://platform.claude.com/settings/keys")!
        case .openai: URL(string: "https://platform.openai.com/api-keys")!
        case .gemini: URL(string: "https://aistudio.google.com/apikey")!
        }
    }

    // MARK: - Keychain identity

    /// Gemini keeps the pre-BYOK service/account pair so existing installs find
    /// the key they already saved; the others follow a uniform scheme.
    var keychainService: String {
        switch self {
        case .gemini: "com.cauchy.gemini-api-key"
        default: "com.cauchy.apikey.\(rawValue)"
        }
    }

    var keychainAccount: String {
        switch self {
        case .gemini: "gemini-api-key"
        default: "\(rawValue)-api-key"
        }
    }

    // MARK: - Connector wiring

    var connectorID: AssistantConnectorID {
        switch self {
        case .anthropic: .anthropicAPI
        case .openai: .openaiAPI
        case .gemini: .gemini
        }
    }

    /// The order background jobs (reference indexing, thread titles) walk when
    /// looking for any saved key: cheapest capable vendor first.
    static let fallbackOrder: [CloudAPIProvider] = [.gemini, .anthropic, .openai]

    /// The cheapest model in this provider's catalog — used for the one-line
    /// jobs (naming a thread) that must not spend a frontier call.
    var economyModelID: String {
        connectorID.connector.models.first { $0.tier == .fast }?.id
            ?? connectorID.connector.models[0].id
    }

    /// What indexing and vision jobs use when this provider is the fallback:
    /// the balanced rung, matching the connector's own default.
    var defaultModelID: String {
        guard case .model(let id) = connectorID.connector.defaultChoice else {
            return connectorID.connector.models[0].id
        }
        return id
    }
}
