import Foundation

/// User preference to ignore the stored Gemini API key and run fully
/// on-device, without having to delete the key from the Keychain.
enum ModelProviderPreferences {
    static let forceOnDeviceModelKey = "forceOnDeviceModel"

    static var forceOnDeviceModel: Bool {
        get { UserDefaults.standard.bool(forKey: forceOnDeviceModelKey) }
        set { UserDefaults.standard.set(newValue, forKey: forceOnDeviceModelKey) }
    }

    /// The Gemini API key to use for chat, indexing, and vision — nil when the
    /// on-device override is active or no key is stored. Every Gemini call
    /// site must obtain the key through this instead of KeychainService.
    static var activeGeminiAPIKey: String? {
        forceOnDeviceModel ? nil : KeychainService.loadGeminiAPIKey()
    }

    static var geminiEnabled: Bool {
        activeGeminiAPIKey != nil
    }
}
