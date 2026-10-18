import Foundation

/// What the user picked in the model selector.
enum AssistantSelection: Equatable {
    /// Resolve at ask-time to the best connector that is actually ready on this
    /// Mac, so the app works out of the box and keeps working when a CLI is
    /// installed or removed later.
    case automatic
    case connector(AssistantConnectorID)

    static let automaticToken = "automatic"

    var storageToken: String {
        switch self {
        case .automatic: Self.automaticToken
        case .connector(let id): id.rawValue
        }
    }

    init(token: String?) {
        guard let token else { self = .automatic; return }
        if let id = AssistantConnectorID(rawValue: token) {
            self = .connector(id)
        } else {
            self = .automatic
        }
    }
}

/// The connector and model an ask will actually use, once `automatic` has been
/// resolved away.
struct ResolvedAssistant {
    let connector: AssistantConnector
    let choice: ModelChoice
    /// True when the user chose Automatic and this is what it landed on.
    let viaAutomatic: Bool
    /// Apple Intelligence is the stored choice, this Mac can't run it, and no
    /// other provider is configured. The ask field stays up and asks for one.
    var needsProviderChoice = false

    /// nil when the connector picks its own model — the app then passes no
    /// `--model` at all.
    var modelID: String? {
        if case .model(let id) = choice { return id }
        return nil
    }

    var model: AssistantModel? { modelID.flatMap(connector.model(id:)) }

    /// Short name for the collapsed picker button.
    var label: String {
        if needsProviderChoice { return "Choose a model" }
        let name = model?.name ?? connector.name
        return viaAutomatic ? "Auto · \(name)" : name
    }
}

enum AssistantPreferences {
    /// Legacy key name, kept so existing installs keep their choice — the
    /// stored values ("automatic" plus the connector raw values) are unchanged.
    static let selectionKey = "assistantProviderChoice"
    private static let legacyForceOnDeviceKey = "forceOnDeviceModel"

    static func modelKey(for id: AssistantConnectorID) -> String {
        "assistantModel.\(id.rawValue)"
    }

    /// The order Automatic walks: a signed-in CLI beats the on-device model,
    /// which beats an API key the user has to pay for separately.
    static let automaticOrder: [AssistantConnectorID] = [
        .claudeCode, .codex, .antigravity, .onDevice,
    ] + AssistantConnectorID.byok

    // MARK: - Selection

    static var selection: AssistantSelection {
        get {
            if let raw = UserDefaults.standard.string(forKey: selectionKey) {
                return AssistantSelection(token: raw)
            }
            // Migrate the pre-picker "always use on-device model" toggle.
            if UserDefaults.standard.bool(forKey: legacyForceOnDeviceKey) {
                return .connector(.onDevice)
            }
            return .automatic
        }
        set {
            UserDefaults.standard.set(newValue.storageToken, forKey: selectionKey)
        }
    }

    static func modelChoice(for id: AssistantConnectorID) -> ModelChoice {
        id.connector.choice(fromToken: UserDefaults.standard.string(forKey: modelKey(for: id)))
    }

    static func setModelChoice(_ choice: ModelChoice, for id: AssistantConnectorID) {
        UserDefaults.standard.set(choice.storageToken, forKey: modelKey(for: id))
    }

    // MARK: - Resolution

    /// What Automatic lands on right now, whether or not it is the current
    /// choice — the picker shows this so Automatic is never a mystery.
    @MainActor
    static var automaticTarget: ResolvedAssistant {
        let order = AppleIntelligenceAvailability.isSupported
            ? automaticOrder
            : automaticOrder.filter { $0 != .onDevice }
        if let id = order.first(where: { $0.connector.isReady }) {
            return ResolvedAssistant(
                connector: id.connector,
                choice: modelChoice(for: id),
                viaAutomatic: true
            )
        }
        if AppleIntelligenceAvailability.isSupported {
            return ResolvedAssistant(
                connector: AssistantConnectorID.onDevice.connector,
                choice: modelChoice(for: .onDevice),
                viaAutomatic: true
            )
        }
        return ResolvedAssistant(
            connector: AssistantConnectorID.onDevice.connector,
            choice: .connectorDefault,
            viaAutomatic: true,
            needsProviderChoice: true
        )
    }

    /// First provider other than Apple Intelligence that can answer right now.
    @MainActor
    static func firstReadyAlternative() -> AssistantConnectorID? {
        automaticOrder.filter { $0 != .onDevice }.first { $0.connector.isReady }
    }

    /// Checkmarks follow this. A stored on-device choice on an older Mac moves
    /// to the provider that will actually be called, without rewriting the
    /// saved preference (it still applies after an upgrade to macOS 27).
    @MainActor
    static func effectiveSelection(for selection: AssistantSelection) -> AssistantSelection {
        guard !AppleIntelligenceAvailability.isSupported else { return selection }
        guard case .connector(.onDevice) = selection else { return selection }
        if let id = firstReadyAlternative() {
            return .connector(id)
        }
        return selection
    }

    @MainActor
    static var resolved: ResolvedAssistant {
        switch selection {
        case .connector(.onDevice) where !AppleIntelligenceAvailability.isSupported:
            if let id = firstReadyAlternative() {
                return ResolvedAssistant(
                    connector: id.connector,
                    choice: modelChoice(for: id),
                    viaAutomatic: false
                )
            }
            return ResolvedAssistant(
                connector: AssistantConnectorID.onDevice.connector,
                choice: .connectorDefault,
                viaAutomatic: false,
                needsProviderChoice: true
            )
        case .connector(let id):
            return ResolvedAssistant(
                connector: id.connector,
                choice: modelChoice(for: id),
                viaAutomatic: false
            )
        case .automatic:
            return automaticTarget
        }
    }

    // MARK: - BYOK keys

    /// Which vendor the background jobs — reference indexing, vision re-index,
    /// thread titles — should call when they need a cloud model. The connector
    /// the user picked for chat wins if it is a BYOK one and has a key;
    /// otherwise the first provider that has a key at all.
    ///
    /// nil when the user explicitly pinned the assistant to the on-device
    /// model: that one choice is what keeps everything local. Choosing a CLI
    /// connector for chat does NOT disable cloud assist here — indexing still
    /// falls back to a saved key when Apple Intelligence is unavailable.
    static var activeCloudProvider: CloudAPIProvider? {
        // Pinning Apple Intelligence keeps indexing local, but only on a Mac
        // that can actually run it. Elsewhere a saved key is still used.
        if selection == .connector(.onDevice), AppleIntelligenceAvailability.isSupported {
            return nil
        }
        if case .connector(let id) = selection,
           let provider = id.connector.apiProvider,
           KeychainService.hasKey(for: provider) {
            return provider
        }
        return CloudAPIProvider.fallbackOrder.first { KeychainService.hasKey(for: $0) }
    }

    /// Same rule as `activeCloudProvider`, but only checks that a key exists
    /// rather than reading one — safe to call from a view body, which
    /// `activeCloudModel(named:)` is not.
    static var cloudAssistEnabled: Bool {
        activeCloudProvider != nil
    }

    /// A ready-to-use model for the active provider, or nil when there is none.
    /// Every cloud call site must obtain its model here rather than from
    /// KeychainService, so the on-device pin keeps everything local.
    static func activeCloudSelection(named modelID: String? = nil) -> CloudModelSelection? {
        guard let provider = activeCloudProvider,
              let apiKey = KeychainService.loadKey(for: provider)
        else { return nil }
        return CloudModelSelection(
            provider: provider,
            apiKey: apiKey,
            modelName: modelID ?? provider.defaultModelID
        )
    }

    @available(macOS 27, *)
    static func activeCloudModel(named modelID: String? = nil) -> CloudLanguageModel? {
        guard let selection = activeCloudSelection(named: modelID) else { return nil }
        return CloudLanguageModel(
            provider: selection.provider,
            apiKey: selection.apiKey,
            modelName: selection.modelName
        )
    }

    /// The cheapest model of the active provider — for the throwaway one-line
    /// jobs that must not spend a frontier call.
    @available(macOS 27, *)
    static func activeEconomyCloudModel() -> CloudLanguageModel? {
        guard let provider = activeCloudProvider else { return nil }
        return activeCloudModel(named: provider.economyModelID)
    }
}
