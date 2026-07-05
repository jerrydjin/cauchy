import Foundation
import FoundationModels

@MainActor
enum ReadingAssistantProviderFactory {
    static func makeAssistant() -> any ReadingAssistantProtocol {
        if let apiKey = KeychainService.loadGeminiAPIKey() {
            return FoundationModelsReadingAssistantService(
                model: GeminiCloudLanguageModel(apiKey: apiKey),
                provider: .gemini
            )
        }
        return FoundationModelsReadingAssistantService(
            model: SystemLanguageModel.default,
            provider: .local
        )
    }

    static var activeProvider: ReadingAssistantProvider {
        KeychainService.hasGeminiAPIKey ? .gemini : .local
    }

    static var availability: ReadingAssistantAvailability {
        if KeychainService.hasGeminiAPIKey {
            return FoundationModelsReadingAssistantService.geminiAvailability
        }
        return FoundationModelsReadingAssistantService.localAvailability
    }
}
