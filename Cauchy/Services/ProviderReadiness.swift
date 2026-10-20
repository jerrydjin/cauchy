import Foundation
import Observation

/// Whether a connector and model have passed a real request. `ready` is the
/// only state that enables the ask box, and it is cached only after success.
enum ReadinessState: Equatable, Sendable {
    case unknown
    case checking
    case ready
    case blocked(AssistantFailure)
}

struct ProbeKey: Hashable, Codable, Sendable {
    var connector: String
    var model: String

    init(connectorID: AssistantConnectorID, modelID: String?) {
        self.connector = connectorID.rawValue
        self.model = modelID ?? ""
    }
}

protocol ProviderProbing: Sendable {
    func probe(connectorID: AssistantConnectorID, modelID: String?) async -> AssistantFailure?
}

/// One tiny request per connector and model. Success is cached. A later
/// failure drops the cache so the next check runs again.
@MainActor @Observable
final class ProviderReadinessStore {
    static let shared = ProviderReadinessStore()

    private static let storageKey = "cauchy.providerReadiness.v1"

    private let defaults: UserDefaults
    private let prober: any ProviderProbing
    private let binaryIsInstalled: @MainActor (AssistantConnectorID) -> Bool
    private let apiKeyIsStored: @MainActor (CloudAPIProvider) -> Bool
    private var generation: [ProbeKey: Int] = [:]

    /// A cached success whose binary or key has since disappeared. Ready must
    /// not come back on its own when that returns; the next check runs again.
    @ObservationIgnored private var suppressedReady: Set<ProbeKey> = []

    private(set) var states: [ProbeKey: ReadinessState] = [:]

    init(
        defaults: UserDefaults = .standard,
        prober: any ProviderProbing = LiveProviderProbe(),
        binaryIsInstalled: @escaping @MainActor (AssistantConnectorID) -> Bool = { $0.connector.resolvedBinaryURL != nil },
        apiKeyIsStored: @escaping @MainActor (CloudAPIProvider) -> Bool = { KeychainService.hasKey(for: $0) }
    ) {
        self.defaults = defaults
        self.prober = prober
        self.binaryIsInstalled = binaryIsInstalled
        self.apiKeyIsStored = apiKeyIsStored
        if let data = defaults.data(forKey: Self.storageKey),
           let keys = try? JSONDecoder().decode([ProbeKey].self, from: data) {
            for key in keys {
                states[key] = .ready
            }
        }
    }

    func state(for connectorID: AssistantConnectorID, modelID: String?) -> ReadinessState {
        let key = ProbeKey(connectorID: connectorID, modelID: modelID)
        let stored = states[key]
        switch connectorID.connector.access {
        case .onDevice:
            return onDeviceState()
        case .cliSignIn:
            if !binaryIsInstalled(connectorID) {
                if case .ready = stored { suppressReady(key) }
                return .blocked(.notInstalled(connectorID))
            }
        case .apiKey(let provider):
            if !apiKeyIsStored(provider) {
                if case .ready = stored { suppressReady(key) }
                return .blocked(.missingAPIKey(provider))
            }
        }
        if case .blocked(.notInstalled) = stored, binaryIsInstalled(connectorID) {
            return .unknown
        }
        if case .blocked(.missingAPIKey) = stored,
           case .apiKey(let provider) = connectorID.connector.access,
           apiKeyIsStored(provider) {
            return .unknown
        }
        // The binary or key went away and came back in this session. The old
        // success is no longer evidence that this model can answer.
        if suppressedReady.contains(key), case .ready = stored {
            return .unknown
        }
        return stored ?? .unknown
    }

    private func suppressReady(_ key: ProbeKey) {
        guard suppressedReady.insert(key).inserted else { return }
        Task { @MainActor in
            guard self.suppressedReady.contains(key) else { return }
            if case .ready = self.states[key] {
                self.states[key] = nil
                self.save()
            }
        }
    }

    func probeIfNeededCurrentSelection() async {
        reconcile()
        switch AssistantPreferences.selection {
        case .connector(let id):
            await probeIfNeeded(connectorID: id, modelID: AssistantPreferences.modelChoice(for: id).modelID)
        case .automatic:
            for id in AssistantPreferences.automaticOrder where id != .onDevice {
                let modelID = AssistantPreferences.modelChoice(for: id).modelID
                switch state(for: id, modelID: modelID) {
                case .ready:
                    return
                case .blocked, .checking:
                    continue
                case .unknown:
                    _ = await probe(connectorID: id, modelID: modelID, force: false)
                    if case .ready = state(for: id, modelID: modelID) { return }
                }
            }
        }
    }

    func probeIfNeeded(connectorID: AssistantConnectorID, modelID: String?) async {
        switch state(for: connectorID, modelID: modelID) {
        case .ready, .blocked, .checking:
            return
        case .unknown:
            _ = await probe(connectorID: connectorID, modelID: modelID, force: false)
        }
    }

    @discardableResult
    func probe(connectorID: AssistantConnectorID, modelID: String?, force: Bool) async -> AssistantFailure? {
        if !force, case .ready = state(for: connectorID, modelID: modelID) {
            return nil
        }
        if connectorID == .onDevice {
            let device = onDeviceState()
            if case .blocked(let failure) = device { return failure }
            return nil
        }
        let key = ProbeKey(connectorID: connectorID, modelID: modelID)
        generation[key, default: 0] += 1
        let token = generation[key]
        states[key] = .checking
        let failure = await prober.probe(connectorID: connectorID, modelID: modelID)
        guard generation[key] == token else { return failure }
        suppressedReady.remove(key)
        if let failure {
            states[key] = .blocked(failure)
        } else {
            states[key] = .ready
        }
        save()
        return failure
    }

    func markReady(connectorID: AssistantConnectorID, modelID: String?) {
        let key = ProbeKey(connectorID: connectorID, modelID: modelID)
        suppressedReady.remove(key)
        states[key] = .ready
        save()
    }

    /// Drops a cached success. The next check has to run a real request again.
    func record(_ failure: AssistantFailure, connectorID: AssistantConnectorID, modelID: String?) {
        if case .cancelled = failure { return }
        let key = ProbeKey(connectorID: connectorID, modelID: modelID)
        suppressedReady.remove(key)
        states[key] = .blocked(failure)
        save()
    }

    func invalidate(connectorID: AssistantConnectorID, modelID: String?) {
        let key = ProbeKey(connectorID: connectorID, modelID: modelID)
        suppressedReady.remove(key)
        states[key] = nil
        generation[key, default: 0] += 1
        save()
    }

    private func onDeviceState() -> ReadinessState {
        switch FoundationModelsReadingAssistantService.localAvailability {
        case .available:
            return .ready
        case .deviceNotEligible:
            return .blocked(.deviceNotEligible)
        case .intelligenceNotEnabled:
            return .blocked(.intelligenceNotEnabled)
        case .modelNotReady:
            return .blocked(.modelNotReady)
        case .cliNotInstalled, .apiKeyMissing, .unavailable:
            return .blocked(.failed(.onDevice, "Apple Intelligence is not available right now."))
        }
    }

    private func reconcile() {
        var stale: [ProbeKey] = []
        for (key, value) in states where value == .ready {
            guard let id = AssistantConnectorID(rawValue: key.connector) else {
                stale.append(key)
                continue
            }
            switch id.connector.access {
            case .cliSignIn where !binaryIsInstalled(id):
                stale.append(key)
            case .apiKey(let provider) where !apiKeyIsStored(provider):
                stale.append(key)
            default:
                break
            }
        }
        guard !stale.isEmpty else { return }
        for key in stale { states[key] = nil }
        save()
    }

    private func save() {
        let ready = states.compactMap { key, value -> ProbeKey? in
            if case .ready = value { return key }
            return nil
        }
        if let data = try? JSONEncoder().encode(ready) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

struct LiveProviderProbe: ProviderProbing {
    func probe(connectorID: AssistantConnectorID, modelID: String?) async -> AssistantFailure? {
        switch connectorID.connector.access {
        case .onDevice:
            return nil
        case .cliSignIn:
            return await CLIReadinessProbe.run(connectorID: connectorID, modelID: modelID)
        case .apiKey(let provider):
            guard KeychainService.hasKey(for: provider),
                  let apiKey = KeychainService.loadKey(for: provider) else {
                return .missingAPIKey(provider)
            }
            let model = modelID ?? provider.defaultModelID
            return await CloudReadinessProbe.run(provider: provider, apiKey: apiKey, modelID: model)
        }
    }
}

enum CLIReadinessProbe {
    static func run(
        connectorID: AssistantConnectorID,
        modelID: String?,
        binary: URL? = nil,
        timeout: TimeInterval = CLIInvocation.probeTimeout
    ) async -> AssistantFailure? {
        let resolved: URL?
        if let binary {
            resolved = binary
        } else if let name = connectorID.connector.binaryName {
            resolved = await CLIAgentRunner.locateBinary(named: name)
        } else {
            resolved = nil
        }
        guard let resolved else { return .notInstalled(connectorID) }

        let prompt = "Reply with exactly OK."
        let arguments: [String]
        switch connectorID {
        case .codex:
            arguments = CLIInvocation.codexArguments(prompt: prompt, modelID: modelID)
        case .antigravity:
            arguments = CLIInvocation.antigravityArguments(prompt: prompt)
        default:
            arguments = CLIInvocation.claudeArguments(
                prompt: prompt,
                instructions: "Reply with exactly OK.",
                modelID: modelID
            )
        }
        let output = await CLIInvocation.execute(
            binary: resolved,
            provider: connectorID,
            arguments: arguments,
            timeout: timeout,
            onPartial: nil
        )
        if output.cancelled { return .cancelled }
        return AssistantFailure.classify(
            connectorID: connectorID,
            modelID: modelID,
            parserError: output.parserError,
            parserText: output.text,
            rawOutput: output.raw,
            processError: output.processError
        )
    }
}

enum CloudReadinessProbe {
    static func run(
        provider: CloudAPIProvider,
        apiKey: String,
        modelID: String,
        session: URLSession = .shared
    ) async -> AssistantFailure? {
        let prompt = CloudPrompt(instructions: "Reply with exactly OK.", prompt: "Reply with exactly OK.")
        do {
            let text = try await CloudStreamingClient.text(
                provider: provider,
                apiKey: apiKey,
                modelName: modelID,
                prompt: prompt,
                session: session,
                requestTimeout: 30
            )
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .emptyOutput(provider.connectorID)
            }
            return nil
        } catch let error as CloudAPIError {
            let modelName = AssistantFailure.displayModelName(connectorID: provider.connectorID, modelID: modelID)
            return AssistantFailure(cloudError: error, provider: provider, modelName: modelName)
        } catch is CancellationError {
            return .cancelled
        } catch let error as URLError where error.code == .timedOut {
            return .timedOut(provider.connectorID)
        } catch {
            return .failed(provider.connectorID, error.localizedDescription)
        }
    }
}
