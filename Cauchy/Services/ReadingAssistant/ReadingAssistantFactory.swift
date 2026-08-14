import Foundation
import FoundationModels

/// Turns the user's connector + model choice into a live assistant. All the
/// knowledge about *what* each connector is lives in `AssistantConnector`; this
/// only knows how to start one.
@MainActor
enum ReadingAssistantFactory {
    static func makeAssistant() -> any ReadingAssistantProtocol {
        // A CLI may have been installed since the last lookup.
        CLIAgentRunner.invalidateBinaryCache()

        let resolved = AssistantPreferences.resolved
        switch resolved.connector.access {
        case .onDevice:
            return localAssistant()

        case .cliSignIn:
            return CLIAgentAssistantService(
                connector: resolved.connector.id,
                modelID: resolved.modelID
            )

        case .apiKey(let apiProvider):
            guard let apiKey = KeychainService.loadKey(for: apiProvider) else {
                // `availability` reports the missing key; the composer stays disabled.
                return localAssistant()
            }
            return FoundationModelsReadingAssistantService(
                model: CloudLanguageModel(
                    provider: apiProvider,
                    apiKey: apiKey,
                    modelName: resolved.modelID
                ),
                provider: resolved.connector.id
            )
        }
    }

    /// The connector answers are currently coming from, after Automatic has
    /// been resolved.
    static var activeConnector: AssistantConnector {
        AssistantPreferences.resolved.connector
    }

    static var availability: ReadingAssistantAvailability {
        activeConnector.availability
    }

    private static func localAssistant() -> any ReadingAssistantProtocol {
        FoundationModelsReadingAssistantService(
            model: SystemLanguageModel.default,
            provider: .onDevice
        )
    }
}
