import SwiftUI

struct SettingsView: View {
    var onSettingsChanged: (() -> Void)?

    @State private var apiKey = ""
    @State private var hasStoredKey = KeychainService.hasGeminiAPIKey
    @State private var statusMessage: String?
    @State private var isError = false
    @AppStorage(ModelProviderPreferences.providerChoiceKey)
    private var providerChoiceRaw = ModelProviderPreferences.providerChoice.rawValue

    init(onSettingsChanged: (() -> Void)? = nil) {
        self.onSettingsChanged = onSettingsChanged
    }

    private var providerChoice: AssistantProviderChoice {
        AssistantProviderChoice(rawValue: providerChoiceRaw) ?? .automatic
    }

    var body: some View {
        Form {
            Section {
                Picker("Ask uses", selection: $providerChoiceRaw) {
                    ForEach(AssistantProviderChoice.allCases) { choice in
                        Text(choice.displayName).tag(choice.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: providerChoiceRaw) { _, _ in
                    onSettingsChanged?()
                }

                providerStatusLabel
            } header: {
                Text("Assistant")
            } footer: {
                Text(providerFooter)
            }

            Section {
                if hasStoredKey {
                    Label("Gemini API key saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                SecureField("Gemini API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Save") {
                        saveKey()
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasStoredKey)

                    Button("Clear", role: .destructive) {
                        clearKey()
                    }
                    .disabled(!hasStoredKey)
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(isError ? .red : .secondary)
                }
            } header: {
                Text("Gemini API Key")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Used when the assistant is set to Automatic or Gemini, and for reference indexing whenever a key is saved.")
                    Link("Get a Gemini API key", destination: URL(string: "https://aistudio.google.com/apikey")!)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 400)
        .padding()
    }

    @ViewBuilder
    private var providerStatusLabel: some View {
        switch providerChoice {
        case .claudeCode, .codex:
            let provider: ReadingAssistantProvider = providerChoice == .codex ? .codex : .claudeCode
            if let binary = CLIAgentAssistantService.binaryURL(for: provider) {
                Label("Found \(binary.path)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            } else {
                Label("\(provider.cliDisplayName) CLI not found", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        case .gemini where !hasStoredKey:
            Label("No Gemini API key saved", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
        default:
            EmptyView()
        }
    }

    private var providerFooter: String {
        switch providerChoice {
        case .automatic:
            return "Uses Gemini when an API key is saved, otherwise on-device Apple Intelligence."
        case .onDevice:
            return "Everything runs locally with Apple Intelligence. No key, no network — and noticeably weaker at mathematics."
        case .gemini:
            return "Answers come from Google Gemini using the API key below."
        case .claudeCode:
            return "Answers come from the Claude Code CLI under your own Claude subscription — no API key needed. Install Claude Code, run `claude` in Terminal once to sign in, and you're set. Tools are disabled: it can never run commands on your Mac."
        case .codex:
            return "Answers come from the Codex CLI under your own ChatGPT plan — no API key needed. Install Codex (`npm i -g @openai/codex` or `brew install codex`), run `codex login` once, and you're set. Runs read-only sandboxed."
        }
    }

    private func saveKey() {
        do {
            try KeychainService.saveGeminiAPIKey(apiKey)
            hasStoredKey = KeychainService.hasGeminiAPIKey
            apiKey = ""
            statusMessage = "API key saved."
            isError = false
            onSettingsChanged?()
        } catch {
            statusMessage = error.localizedDescription
            isError = true
        }
    }

    private func clearKey() {
        do {
            try KeychainService.deleteGeminiAPIKey()
            hasStoredKey = false
            apiKey = ""
            statusMessage = "API key removed."
            isError = false
            onSettingsChanged?()
        } catch {
            statusMessage = error.localizedDescription
            isError = true
        }
    }
}
