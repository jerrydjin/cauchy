import Foundation
import FoundationModels

@MainActor
enum ReadingAssistantProviderFactory {
    static func makeAssistant() -> any ReadingAssistantProtocol {
        // A CLI may have been installed since the last lookup.
        CLIAgentRunner.invalidateBinaryCache()

        switch ModelProviderPreferences.providerChoice {
        case .automatic:
            if let apiKey = ModelProviderPreferences.activeGeminiAPIKey {
                return geminiAssistant(apiKey: apiKey)
            }
            return localAssistant()
        case .onDevice:
            return localAssistant()
        case .gemini:
            if let apiKey = KeychainService.loadGeminiAPIKey() {
                return geminiAssistant(apiKey: apiKey)
            }
            // Availability reports the missing key; the composer stays disabled.
            return localAssistant()
        case .claudeCode:
            return CLIAgentAssistantService(provider: .claudeCode)
        case .codex:
            return CLIAgentAssistantService(provider: .codex)
        }
    }

    static var activeProvider: ReadingAssistantProvider {
        switch ModelProviderPreferences.providerChoice {
        case .automatic:
            return ModelProviderPreferences.geminiEnabled ? .gemini : .local
        case .onDevice:
            return .local
        case .gemini:
            return .gemini
        case .claudeCode:
            return .claudeCode
        case .codex:
            return .codex
        }
    }

    static var availability: ReadingAssistantAvailability {
        switch ModelProviderPreferences.providerChoice {
        case .automatic:
            if ModelProviderPreferences.geminiEnabled {
                return FoundationModelsReadingAssistantService.geminiAvailability
            }
            return FoundationModelsReadingAssistantService.localAvailability
        case .onDevice:
            return FoundationModelsReadingAssistantService.localAvailability
        case .gemini:
            return FoundationModelsReadingAssistantService.geminiAvailability
        case .claudeCode:
            return CLIAgentAssistantService.availability(for: .claudeCode)
        case .codex:
            return CLIAgentAssistantService.availability(for: .codex)
        }
    }

    private static func geminiAssistant(apiKey: String) -> any ReadingAssistantProtocol {
        FoundationModelsReadingAssistantService(
            model: GeminiCloudLanguageModel(
                apiKey: apiKey,
                modelName: ModelProviderPreferences.selectedModelID(for: .gemini)
            ),
            provider: .gemini
        )
    }

    private static func localAssistant() -> any ReadingAssistantProtocol {
        FoundationModelsReadingAssistantService(
            model: SystemLanguageModel.default,
            provider: .local
        )
    }
}
