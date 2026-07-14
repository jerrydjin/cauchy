import Foundation

/// Which brain answers Ask questions. Persisted in UserDefaults and read by
/// ReadingAssistantProviderFactory; the Gemini key also feeds reference
/// indexing regardless of the chat choice (unless forced fully on-device).
enum AssistantProviderChoice: String, CaseIterable, Identifiable {
    /// Gemini when a key is saved, otherwise on-device Apple Intelligence.
    case automatic
    case onDevice
    case gemini
    case claudeCode
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .onDevice: "Apple Intelligence (on-device)"
        case .gemini: "Gemini (API key)"
        case .claudeCode: "Claude Code (CLI sign-in)"
        case .codex: "Codex (CLI sign-in)"
        }
    }
}

enum ModelProviderPreferences {
    static let providerChoiceKey = "assistantProviderChoice"
    private static let legacyForceOnDeviceKey = "forceOnDeviceModel"

    static var providerChoice: AssistantProviderChoice {
        get {
            if let raw = UserDefaults.standard.string(forKey: providerChoiceKey),
               let choice = AssistantProviderChoice(rawValue: raw) {
                return choice
            }
            // Migrate the pre-picker "always use on-device model" toggle.
            if UserDefaults.standard.bool(forKey: legacyForceOnDeviceKey) {
                return .onDevice
            }
            return .automatic
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: providerChoiceKey)
        }
    }

    /// The Gemini API key to use for chat, indexing, and vision — nil when the
    /// user forced fully on-device operation or no key is stored. Every Gemini
    /// call site must obtain the key through this instead of KeychainService.
    /// Note: choosing a CLI provider for chat does NOT disable Gemini here;
    /// reference indexing still benefits from the key.
    static var activeGeminiAPIKey: String? {
        providerChoice == .onDevice ? nil : KeychainService.loadGeminiAPIKey()
    }

    static var geminiEnabled: Bool {
        activeGeminiAPIKey != nil
    }
}
