import SwiftUI

/// Compact model selector shown in the conversation composer. One menu picks
/// both the provider and the model: choosing "Claude Opus 4.8" switches the
/// assistant to Claude Code running Opus. Selection is shared with the
/// Settings provider picker via the same UserDefaults keys.
struct ModelPickerMenu: View {
    /// Called after the selection is persisted so the workspace can swap the
    /// live assistant without losing the current thread.
    var onChange: () -> Void

    @AppStorage(ModelProviderPreferences.providerChoiceKey)
    private var providerChoiceRaw = ModelProviderPreferences.providerChoice.rawValue
    @AppStorage(ModelProviderPreferences.geminiModelKey)
    private var geminiModelRaw = ModelProviderPreferences.selectedModelID(for: .gemini)
    @AppStorage(ModelProviderPreferences.claudeCodeModelKey)
    private var claudeModelRaw = ModelProviderPreferences.selectedModelID(for: .claudeCode)
    @AppStorage(ModelProviderPreferences.codexModelKey)
    private var codexModelRaw = ModelProviderPreferences.selectedModelID(for: .codex)

    var body: some View {
        Menu {
            Picker("Model", selection: selectionToken) {
                Text("Automatic").tag("automatic")

                Section("On-Device") {
                    Text("Apple Intelligence").tag("onDevice")
                }
                modelSection(title: "Google Gemini", provider: .gemini)
                modelSection(title: "Claude Code", provider: .claudeCode)
                modelSection(title: "Codex", provider: .codex)
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .semibold))
                Text(currentLabel)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .glassEffect(in: .capsule)
        .accessibilityLabel("Model: \(currentLabel)")
        .help("Choose which model answers questions")
    }

    private func modelSection(title: String, provider: AssistantProviderChoice) -> some View {
        Section(title) {
            ForEach(AssistantModelCatalog.models(for: provider)) { model in
                Text(model.displayName).tag("\(provider.rawValue):\(model.id)")
            }
        }
    }

    // MARK: - Selection plumbing

    private var providerChoice: AssistantProviderChoice {
        AssistantProviderChoice(rawValue: providerChoiceRaw) ?? .automatic
    }

    /// "automatic" / "onDevice" / "<provider>:<modelID>".
    private var selectionToken: Binding<String> {
        Binding {
            switch providerChoice {
            case .automatic: return "automatic"
            case .onDevice: return "onDevice"
            case .gemini: return "gemini:\(geminiModelRaw)"
            case .claudeCode: return "claudeCode:\(claudeModelRaw)"
            case .codex: return "codex:\(codexModelRaw)"
            }
        } set: { token in
            apply(token: token)
        }
    }

    private func apply(token: String) {
        switch token {
        case "automatic":
            providerChoiceRaw = AssistantProviderChoice.automatic.rawValue
        case "onDevice":
            providerChoiceRaw = AssistantProviderChoice.onDevice.rawValue
        default:
            let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let provider = AssistantProviderChoice(rawValue: parts[0]),
                  AssistantModelCatalog.model(id: parts[1], for: provider) != nil else {
                return
            }
            switch provider {
            case .gemini: geminiModelRaw = parts[1]
            case .claudeCode: claudeModelRaw = parts[1]
            case .codex: codexModelRaw = parts[1]
            case .automatic, .onDevice: break
            }
            providerChoiceRaw = provider.rawValue
        }
        onChange()
    }

    private var currentLabel: String {
        switch providerChoice {
        case .automatic:
            // Surface what Automatic resolves to, so the default is never a mystery.
            if ModelProviderPreferences.geminiEnabled,
               let model = AssistantModelCatalog.model(id: geminiModelRaw, for: .gemini) {
                return "Auto · \(model.displayName)"
            }
            return "Auto · On-Device"
        case .onDevice:
            return "Apple Intelligence"
        case .gemini:
            return AssistantModelCatalog.model(id: geminiModelRaw, for: .gemini)?.displayName ?? "Gemini"
        case .claudeCode:
            return AssistantModelCatalog.model(id: claudeModelRaw, for: .claudeCode)?.displayName ?? "Claude"
        case .codex:
            return AssistantModelCatalog.model(id: codexModelRaw, for: .codex)?.displayName ?? "Codex"
        }
    }
}
