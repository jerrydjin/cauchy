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

    /// nil when the connector picks its own model — the app then passes no
    /// `--model` at all.
    var modelID: String? {
        if case .model(let id) = choice { return id }
        return nil
    }

    var model: AssistantModel? { modelID.flatMap(connector.model(id:)) }

    /// Short name for the collapsed picker button.
    var label: String {
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
        .claudeCode, .codex, .antigravity, .onDevice, .gemini,
    ]

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
        let id = automaticOrder.first { $0.connector.isReady } ?? .onDevice
        return ResolvedAssistant(
            connector: id.connector,
            choice: modelChoice(for: id),
            viaAutomatic: true
        )
    }

    @MainActor
    static var resolved: ResolvedAssistant {
        switch selection {
        case .connector(let id):
            ResolvedAssistant(
                connector: id.connector,
                choice: modelChoice(for: id),
                viaAutomatic: false
            )
        case .automatic:
            automaticTarget
        }
    }

    // MARK: - Gemini key

    /// The Gemini API key for chat, indexing and vision — nil when the user
    /// explicitly pinned the assistant to the on-device model. Every Gemini
    /// call site must obtain the key here rather than from KeychainService, so
    /// that one choice keeps everything local.
    ///
    /// Note: choosing a CLI connector for chat does NOT disable Gemini here;
    /// reference indexing still falls back to the key when Apple Intelligence
    /// is unavailable.
    static var activeGeminiAPIKey: String? {
        selection == .connector(.onDevice) ? nil : KeychainService.loadGeminiAPIKey()
    }

    /// Same rule as `activeGeminiAPIKey`, but only checks that a key exists —
    /// safe to call from a view body, which `activeGeminiAPIKey` is not.
    static var geminiEnabled: Bool {
        selection != .connector(.onDevice) && KeychainService.hasGeminiAPIKey
    }
}
