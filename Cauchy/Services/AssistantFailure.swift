import Foundation

/// A provider failure the assistant can show and recover from. Nothing in
/// here is fatal: every CLI and cloud outcome becomes one of these cases.
enum AssistantFailure: LocalizedError, Equatable, Sendable {
    case notInstalled(AssistantConnectorID)
    case notSignedIn(AssistantConnectorID)
    case modelUnavailable(AssistantConnectorID, modelName: String)
    case missingAPIKey(CloudAPIProvider)
    case invalidAPIKey(CloudAPIProvider)
    case timedOut(AssistantConnectorID)
    case cancelled
    case emptyOutput(AssistantConnectorID)
    case unreadableOutput(AssistantConnectorID)
    case failed(AssistantConnectorID, String)
    case deviceNotEligible
    case intelligenceNotEnabled
    case modelNotReady

    var errorDescription: String? { statusLine }

    /// Sentence under the ask box, and the chat bubble when a request fails.
    var statusLine: String {
        switch self {
        case .notInstalled(let id):
            return "\(id.connector.name) is not installed."
        case .notSignedIn(let id):
            return "\(id.connector.name) is not signed in."
        case .modelUnavailable(let id, let modelName):
            return "\(modelName) isn't available in \(id.connector.name). Choose another model."
        case .missingAPIKey(let provider):
            return "Add your \(provider.vendor) API key to ask questions."
        case .invalidAPIKey(let provider):
            return "The \(provider.vendor) API key is invalid. Update it in Settings."
        case .timedOut(let id):
            return "\(id.connector.name) took too long to respond. Try again."
        case .cancelled:
            return "The request was cancelled."
        case .emptyOutput(let id):
            return "\(id.connector.name) produced no response."
        case .unreadableOutput(let id):
            return "\(id.connector.name) returned a response Cauchy couldn't read."
        case .failed(let id, let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return "\(id.connector.name) couldn't answer." }
            return trimmed
        case .deviceNotEligible:
            return "Apple Intelligence is not supported on this Mac."
        case .intelligenceNotEnabled:
            return "Turn on Apple Intelligence in System Settings to ask questions."
        case .modelNotReady:
            return "The on-device model is still downloading. Try again soon."
        }
    }

    /// Two or three words for a disabled menu row.
    var menuNote: String {
        switch self {
        case .notInstalled: "not installed"
        case .notSignedIn: "not signed in"
        case .modelUnavailable: "model unavailable"
        case .missingAPIKey: "needs a key"
        case .invalidAPIKey: "invalid key"
        case .timedOut: "timed out"
        case .cancelled, .emptyOutput, .unreadableOutput, .failed: "not ready"
        case .deviceNotEligible, .intelligenceNotEnabled, .modelNotReady: "unavailable"
        }
    }

    var connectorID: AssistantConnectorID? {
        switch self {
        case .notInstalled(let id), .notSignedIn(let id), .modelUnavailable(let id, _),
             .timedOut(let id), .emptyOutput(let id), .unreadableOutput(let id), .failed(let id, _):
            return id
        case .missingAPIKey(let provider), .invalidAPIKey(let provider):
            return provider.connectorID
        case .cancelled, .deviceNotEligible, .intelligenceNotEnabled, .modelNotReady:
            return nil
        }
    }

    /// The one next step, when Cauchy can offer it. Model choice stays in the
    /// picker so a failure never silently changes provider.
    var recovery: AskRecovery? {
        switch self {
        case .notInstalled(let id), .notSignedIn(let id):
            return .setup(id)
        case .missingAPIKey, .invalidAPIKey:
            return .settings
        case .timedOut(let id), .emptyOutput(let id), .unreadableOutput(let id), .failed(let id, _):
            return .retry(id)
        case .modelUnavailable, .cancelled, .deviceNotEligible, .intelligenceNotEnabled, .modelNotReady:
            return nil
        }
    }

    var recoveryTitle: String? {
        switch self {
        case .notInstalled(let id):
            return "Install \(id.connector.name) to start asking"
        case .notSignedIn(let id):
            return signInTitle(for: id)
        case .missingAPIKey(let provider):
            return "Add your \(provider.vendor) API key to start asking"
        case .invalidAPIKey(let provider):
            return "Update your \(provider.vendor) API key to start asking"
        case .timedOut, .emptyOutput, .unreadableOutput, .failed:
            return "Try again"
        case .modelUnavailable, .cancelled, .deviceNotEligible, .intelligenceNotEnabled, .modelNotReady:
            return nil
        }
    }

    func askPresentation() -> AskPresentation {
        AskPresentation(
            canAsk: false,
            message: statusLine,
            buttonTitle: recoveryTitle,
            recovery: recovery
        )
    }

    static func signInTitle(for id: AssistantConnectorID) -> String {
        switch id {
        case .codex: "Sign in to ChatGPT to start asking"
        case .claudeCode: "Sign in to Claude to start asking"
        case .antigravity: "Sign in to Google to start asking"
        default: "Sign in to \(id.connector.name) to start asking"
        }
    }

    static func displayModelName(connectorID: AssistantConnectorID, modelID: String?) -> String {
        if let modelID, let model = connectorID.connector.model(id: modelID) {
            return model.name
        }
        if let modelID, !modelID.isEmpty { return modelID }
        return connectorID.connector.name
    }

    init(cloudError: CloudAPIError, provider: CloudAPIProvider, modelName: String) {
        let id = provider.connectorID
        switch cloudError {
        case .invalidAPIKey:
            self = .invalidAPIKey(provider)
        case .modelUnavailable:
            self = .modelUnavailable(id, modelName: modelName)
        case .rateLimited:
            self = .failed(id, "\(provider.vendor) rate limit reached. Try again in a moment.")
        case .network(let message):
            if message.lowercased().contains("timed out") {
                self = .timedOut(id)
            } else {
                self = .failed(id, "Network error: \(message)")
            }
        case .api(let message):
            if Self.isAuthenticationFailure(message) {
                self = .invalidAPIKey(provider)
            } else if Self.isModelFailure(message) {
                self = .modelUnavailable(id, modelName: modelName)
            } else {
                self = .failed(id, message)
            }
        }
    }

    /// nil means the run produced an answer. Every other outcome is a failure
    /// the panel can show. Auth and model checks run only when the run did
    /// not succeed, so an answer that mentions signing in is left alone.
    static func classify(
        connectorID: AssistantConnectorID,
        modelID: String?,
        parserError: String?,
        parserText: String?,
        rawOutput: String,
        processError: CLIAgentError?
    ) -> AssistantFailure? {
        if case .timedOut = processError {
            return .timedOut(connectorID)
        }
        if case .launchFailed(let message) = processError {
            return .failed(connectorID, "Could not launch \(connectorID.connector.name): \(message)")
        }

        let name = connectorID.connector.name
        let modelName = displayModelName(connectorID: connectorID, modelID: modelID)
        let stderr: String
        let exitCode: Int32?
        if case .processFailed(let code, let err) = processError {
            exitCode = code
            stderr = err
        } else {
            exitCode = processError == nil ? 0 : nil
            stderr = ""
        }
        let blob = [parserError, stderr, rawOutput]
            .compactMap { $0 }
            .joined(separator: "\n")
        let text = parserText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parserProblem = parserError?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let succeeded = processError == nil && parserProblem.isEmpty && !text.isEmpty
        if succeeded { return nil }

        if isAuthenticationFailure(blob) || exitCode == 2 {
            return .notSignedIn(connectorID)
        }
        if isModelFailure(blob) || (exitCode == 4 && blob.lowercased().contains("model")) {
            return .modelUnavailable(connectorID, modelName: modelName)
        }
        if !parserProblem.isEmpty {
            return .failed(connectorID, parserProblem)
        }
        if let exitCode, exitCode != 0 {
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return .failed(connectorID, "\(name) exited with code \(exitCode).")
            }
            return .failed(connectorID, detail)
        }
        if rawOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if connectorID == .antigravity {
                return .failed(connectorID, "Antigravity produced no response. This usually means its quota is exhausted or sign-in expired — run `agy` in Terminal to check.")
            }
            return .emptyOutput(connectorID)
        }
        return .unreadableOutput(connectorID)
    }

    static func isAuthenticationFailure(_ text: String) -> Bool {
        let value = text.lowercased()
        let needles = [
            "not logged in", "not signed in", "login required", "please log in",
            "please login", "sign in to", "signin required", "authentication",
            "unauthorized", "invalid api key", "invalid_api_key", "auth login",
            "authentication_failed", "not authenticated", "codex login",
            "claude auth login", "run `codex login`",
        ]
        return needles.contains { value.contains($0) }
    }

    static func isModelFailure(_ text: String) -> Bool {
        let value = text.lowercased()
        guard value.contains("model") else { return false }
        let needles = [
            "not supported", "not found", "unknown", "does not exist", "doesn't exist",
            "unavailable", "invalid model", "unrecognized", "no such model",
            "cannot be used", "not available", "is not supported",
        ]
        return needles.contains { value.contains($0) }
    }
}

enum AskRecovery: Equatable, Sendable {
    /// Open the existing install / sign-in sheet (embedded terminal).
    case setup(AssistantConnectorID)
    case settings
    case retry(AssistantConnectorID)
}

struct AskPresentation: Equatable, Sendable {
    var canAsk: Bool
    var message: String?
    var buttonTitle: String?
    var recovery: AskRecovery?

    /// Changes when the ask box's step changes, so a view can re-check without
    /// cancelling the check that is already running. Unknown and checking share
    /// a token on purpose: moving into "checking" must not cancel that probe.
    var probeToken: String {
        "\(canAsk)|\(message ?? "")|\(buttonTitle ?? "")"
    }

    static func make(connector: AssistantConnector, state: ReadinessState) -> AskPresentation {
        switch state {
        case .ready:
            return AskPresentation(canAsk: true, message: nil, buttonTitle: nil, recovery: nil)
        case .unknown, .checking:
            return AskPresentation(
                canAsk: false,
                message: "Checking whether \(connector.name) can answer…",
                buttonTitle: nil,
                recovery: nil
            )
        case .blocked(let failure):
            return failure.askPresentation()
        }
    }

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
