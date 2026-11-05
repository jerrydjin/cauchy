import Foundation
import FoundationModels

extension AssistantConnector {
    /// Live availability, resolved the same way for the picker, Settings and
    /// the assistant factory. Indexing and Automatic wait for a successful
    /// probe. A question the reader already sent does not: the assistant
    /// runs it without consulting this.
    @MainActor
    var availability: ReadingAssistantAvailability {
        switch access {
        case .onDevice:
            return FoundationModelsReadingAssistantService.localAvailability
        case .cliSignIn(let binary, _, _):
            if CLIAgentRunner.locateBinary(named: binary) == nil {
                return .cliNotInstalled(id)
            }
            return status.isReady ? .available(id) : .unavailable
        case .apiKey(let provider):
            if !KeychainService.hasKey(for: provider) {
                return .apiKeyMissing(provider)
            }
            return status.isReady ? .available(id) : .unavailable
        }
    }

    @MainActor
    var status: ConnectorStatus {
        let modelID = AssistantPreferences.modelChoice(for: id).modelID
        let readiness = ProviderReadinessStore.shared.state(for: id, modelID: modelID)
        return ConnectorStatus.resolved(access: access, name: name, readiness: readiness)
    }

    @MainActor
    var isReady: Bool { status.isReady }

    /// Where the binary was found, for the Settings diagnostics line.
    @MainActor
    var resolvedBinaryURL: URL? {
        binaryName.flatMap(CLIAgentRunner.locateBinary(named:))
    }
}

extension AskPresentation {
    @MainActor
    static func current() -> AskPresentation {
        let resolved = AssistantPreferences.resolved
        let state = ProviderReadinessStore.shared.state(
            for: resolved.connector.id,
            modelID: resolved.modelID
        )
        return make(connector: resolved.connector, state: state)
    }
}
