import Foundation
import FoundationModels

@MainActor
enum ReadingAssistantProviderFactory {
    static func makeAssistant() -> any ReadingAssistantProtocol {
        if let apiKey = ModelProviderPreferences.activeGeminiAPIKey {
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
        ModelProviderPreferences.geminiEnabled ? .gemini : .local
    }

    static var availability: ReadingAssistantAvailability {
        if ModelProviderPreferences.geminiEnabled {
            return FoundationModelsReadingAssistantService.geminiAvailability
        }
        return FoundationModelsReadingAssistantService.localAvailability
    }
}
