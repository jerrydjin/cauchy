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
                // A missing key must not fall through to Apple Intelligence.
                // The composer stays on the connector the reader picked.
                return UnavailableReadingAssistant(
                    provider: resolved.connector.id,
                    availability: .apiKeyMissing(apiProvider)
                )
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

/// Stands in for a connector that cannot answer yet. It never calls another
/// provider, so a missing key cannot silently become Apple Intelligence.
@MainActor
final class UnavailableReadingAssistant: ReadingAssistantProtocol {
    let provider: AssistantConnectorID
    let availability: ReadingAssistantAvailability
    var isResponding = false

    init(provider: AssistantConnectorID, availability: ReadingAssistantAvailability) {
        self.provider = provider
        self.availability = availability
    }

    func resetSession(context: ReadingContext) {}

    func restoreSession(context: ReadingContext, messages: [ThreadMessage]) {}

    func ask(
        question: String,
        retrieval: AskRetrieval,
        onPartial: ((String) -> Void)?
    ) async throws -> String {
        throw ReadingAssistantError.notAvailable(availability)
    }
}
