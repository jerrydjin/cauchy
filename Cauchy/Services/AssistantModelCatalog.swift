import Foundation

/// One selectable model within a provider. `id` is what gets persisted and,
/// for Gemini, doubles as the API model name.
struct AssistantModel: Identifiable, Hashable {
    let id: String
    let displayName: String
    let detail: String
}

/// The models each provider can chat with. Kept separate from provider
/// selection so the picker can offer both in a single menu.
enum AssistantModelCatalog {
    static func models(for provider: AssistantProviderChoice) -> [AssistantModel] {
        switch provider {
        case .gemini:
            return [
                AssistantModel(
                    id: "gemini-3.5-flash",
                    displayName: "Gemini 3.5 Flash",
                    detail: "Balanced speed and intelligence"
                ),
                AssistantModel(
                    id: "gemini-3.1-pro-preview",
                    displayName: "Gemini 3.1 Pro",
                    detail: "Most capable (preview)"
                ),
                AssistantModel(
                    id: "gemini-3.1-flash-lite",
                    displayName: "Gemini 3.1 Flash-Lite",
                    detail: "Fastest"
                ),
            ]
        case .claudeCode:
            return [
                AssistantModel(
                    id: "claude-sonnet-5",
                    displayName: "Claude Sonnet 5",
                    detail: "Balanced speed and intelligence"
                ),
                AssistantModel(
                    id: "claude-opus-4-8",
                    displayName: "Claude Opus 4.8",
                    detail: "Most capable"
                ),
                AssistantModel(
                    id: "claude-haiku-4-5",
                    displayName: "Claude Haiku 4.5",
                    detail: "Fastest"
                ),
            ]
        case .codex:
            return [
                AssistantModel(
                    id: "gpt-5.6-terra",
                    displayName: "GPT-5.6 Terra",
                    detail: "Balanced speed and intelligence"
                ),
                AssistantModel(
                    id: "gpt-5.6-sol",
                    displayName: "GPT-5.6 Sol",
                    detail: "Most capable"
                ),
                AssistantModel(
                    id: "gpt-5.6-luna",
                    displayName: "GPT-5.6 Luna",
                    detail: "Fastest"
                ),
            ]
        case .automatic, .onDevice:
            return []
        }
    }

    static func defaultModel(for provider: AssistantProviderChoice) -> AssistantModel? {
        models(for: provider).first
    }

    static func model(id: String, for provider: AssistantProviderChoice) -> AssistantModel? {
        models(for: provider).first { $0.id == id }
    }
}

extension ModelProviderPreferences {
    static let geminiModelKey = "assistantModel.gemini"
    static let claudeCodeModelKey = "assistantModel.claudeCode"
    static let codexModelKey = "assistantModel.codex"

    static func modelStorageKey(for provider: AssistantProviderChoice) -> String? {
        switch provider {
        case .gemini: geminiModelKey
        case .claudeCode: claudeCodeModelKey
        case .codex: codexModelKey
        case .automatic, .onDevice: nil
        }
    }

    /// The persisted model for a provider, falling back to the catalog default
    /// when nothing is stored or the stored id no longer exists.
    static func selectedModelID(for provider: AssistantProviderChoice) -> String {
        guard let key = modelStorageKey(for: provider),
              let fallback = AssistantModelCatalog.defaultModel(for: provider) else {
            return ""
        }
        if let raw = UserDefaults.standard.string(forKey: key),
           AssistantModelCatalog.model(id: raw, for: provider) != nil {
            return raw
        }
        return fallback.id
    }

    static func setSelectedModelID(_ id: String, for provider: AssistantProviderChoice) {
        guard let key = modelStorageKey(for: provider) else { return }
        UserDefaults.standard.set(id, forKey: key)
    }
}
