import Foundation
import FoundationModels

/// Whether a connector can actually answer a question on this Mac right now.
enum ConnectorStatus: Equatable {
    /// Usable. The string is a short badge ("Ready", "On-device").
    case ready(String)
    /// One user action away. `hint` is the sentence; `note` is the menu suffix.
    case needsSetup(hint: String, note: String)
    /// Not usable on this machine, and not because of anything they skipped.
    case unavailable(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    /// Setup is still a choice. Only a machine that cannot run the connector
    /// is missing from the picker — otherwise the ask box explains the step.
    var allowsSelection: Bool {
        if case .unavailable = self { return false }
        return true
    }

    var badge: String {
        switch self {
        case .ready(let text): text
        case .needsSetup: "Set up"
        case .unavailable: "Unavailable"
        }
    }

    /// The sentence shown under an unusable connector, nil when it works.
    var hint: String? {
        switch self {
        case .ready: nil
        case .needsSetup(let hint, _): hint
        case .unavailable(let text): text
        }
    }

    /// Two or three words for a menu row, nil when the connector works.
    var shortNote: String? {
        switch self {
        case .ready: nil
        case .needsSetup(_, let note): note
        case .unavailable: "unavailable"
        }
    }
}

extension AssistantConnector {
    /// Live availability, resolved the same way for the picker, Settings and
    /// the assistant factory.
    @MainActor
    var availability: ReadingAssistantAvailability {
        switch access {
        case .onDevice:
            return FoundationModelsReadingAssistantService.localAvailability
        case .cliSignIn(let binary, _, _):
            if CLIAgentRunner.locateBinary(named: binary) == nil {
                return .cliNotInstalled(id)
            }
            // Installed is not the same as able to answer. The ask box stays
            // closed until a real request for this model has succeeded.
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
        switch access {
        case .onDevice:
            switch readiness {
            case .ready:
                return .ready("On-device")
            case .blocked(let failure):
                switch failure {
                case .deviceNotEligible:
                    return .unavailable("This Mac isn't eligible for Apple Intelligence.")
                case .modelNotReady:
                    return .unavailable("The on-device model is still downloading.")
                case .intelligenceNotEnabled:
                    return .needsSetup(hint: failure.statusLine, note: "not enabled")
                default:
                    return .unavailable(failure.statusLine)
                }
            case .unknown, .checking:
                return .needsSetup(hint: "Checking Apple Intelligence…", note: "checking")
            }
        case .cliSignIn, .apiKey:
            switch readiness {
            case .ready:
                return .ready("Ready")
            case .unknown, .checking:
                return .needsSetup(hint: "Checking whether \(name) can answer…", note: "checking")
            case .blocked(let failure):
                return .needsSetup(hint: failure.statusLine, note: failure.menuNote)
            }
        }
    }

    @MainActor
    var isReady: Bool { status.isReady }

    /// Where the binary was found, for the Settings diagnostics line.
    @MainActor
    var resolvedBinaryURL: URL? {
        binaryName.flatMap(CLIAgentRunner.locateBinary(named:))
    }
}
