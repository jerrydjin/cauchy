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
        if resolved.needsProviderChoice {
            return UnconfiguredReadingAssistant()
        }
        switch resolved.connector.access {
        case .onDevice:
            if #available(macOS 27, *) {
                return localAssistant()
            }
            return UnconfiguredReadingAssistant()

        case .cliSignIn:
            return CLIAgentAssistantService(
                connector: resolved.connector.id,
                modelID: resolved.modelID
            )

        case .apiKey(let apiProvider):
            guard let apiKey = KeychainService.loadKey(for: apiProvider) else {
                // `availability` reports the missing key; the composer stays disabled.
                if #available(macOS 27, *) {
                    return localAssistant()
                }
                return UnconfiguredReadingAssistant()
            }
            if #available(macOS 27, *) {
                return FoundationModelsReadingAssistantService(
                    model: CloudLanguageModel(
                        provider: apiProvider,
                        apiKey: apiKey,
                        modelName: resolved.modelID
                    ),
                    provider: resolved.connector.id
                )
            }
            return DirectCloudReadingAssistantService(
                provider: resolved.connector.id,
                apiProvider: apiProvider,
                apiKey: apiKey,
                modelName: resolved.modelID
            )
        }
    }

    /// The connector answers are currently coming from, after Automatic has
    /// been resolved.
    static var activeConnector: AssistantConnector {
        AssistantPreferences.resolved.connector
    }

    static var availability: ReadingAssistantAvailability {
        let resolved = AssistantPreferences.resolved
        if resolved.needsProviderChoice {
            return .chooseProvider
        }
        return resolved.connector.availability
    }

    @available(macOS 27, *)
    private static func localAssistant() -> any ReadingAssistantProtocol {
        FoundationModelsReadingAssistantService(
            model: SystemLanguageModel.default,
            provider: .onDevice
        )
    }
}
