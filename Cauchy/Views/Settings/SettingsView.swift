import SwiftUI

struct SettingsView: View {
    var onSettingsChanged: (() -> Void)?

    @State private var apiKey = ""
    @State private var hasStoredKey = KeychainService.hasGeminiAPIKey
    @State private var statusMessage: String?
    @State private var isError = false
    @State private var showKeySection = false
    @AppStorage(AssistantPreferences.selectionKey)
    private var selectionToken = AssistantSelection.automaticToken

    init(onSettingsChanged: (() -> Void)? = nil) {
        self.onSettingsChanged = onSettingsChanged
    }

    /// Reads `selectionToken` so SwiftUI re-renders this view when the picker
    /// writes a new choice.
    private var activeConnector: AssistantConnector {
        switch AssistantSelection(token: selectionToken) {
        case .automatic: AssistantPreferences.automaticTarget.connector
        case .connector(let id): id.connector
        }
    }

    var body: some View {
        Form {
            Section {
                // Deliberately not a LabeledContent: its value slot swallows the
                // menu's clicks and the picker never opens.
                HStack {
                    Text("Ask uses")
                    Spacer()
                    ModelPicker(style: .settings) {
                        onSettingsChanged?()
                    }
                }
                Text(activeConnector.tagline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Assistant")
            }

            Section {
                ForEach(AssistantConnector.primary) { connector in
                    connectorRow(connector)
                }
            } header: {
                Text("Connectors")
            } footer: {
                Text("Each of these runs under a sign-in you already have — the app never sees a credential. Install or sign in from Terminal; the list refreshes when you reopen Settings.")
            }

            Section {
                DisclosureGroup(isExpanded: $showKeySection) {
                    VStack(alignment: .leading, spacing: 10) {
                        geminiKeyControls
                    }
                    .padding(.top, 6)
                } label: {
                    Label("Gemini API key", systemImage: "key")
                }
            } header: {
                Text("Advanced")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 540)
        .padding()
    }

    // MARK: - Connector status

    @ViewBuilder
    private func connectorRow(_ connector: AssistantConnector) -> some View {
        let status = connector.status

        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: connector.symbol)
                    .frame(width: 16)
                Text(connector.name)
                Spacer()
                Label(status.badge, systemImage: status.isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(status.isReady ? Color.green : Color.orange)
                    .labelStyle(.titleAndIcon)
            }

            // When it works, show where it was found; when it doesn't, show the
            // one thing the user has to do about it.
            Group {
                if let hint = status.hint {
                    Text(hint)
                } else if let path = connector.resolvedBinaryURL?.path {
                    Text(path)
                } else {
                    Text(connector.tagline)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }

    // MARK: - Gemini key

    @ViewBuilder
    private var geminiKeyControls: some View {
        Text("A direct Gemini API key is billed to you per request, so it sits apart from the connectors above. It is also the fallback used for reference indexing when Apple Intelligence is unavailable.")
            .font(.caption)
            .foregroundStyle(.secondary)

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

            Spacer()

            Link("Get a key", destination: URL(string: "https://aistudio.google.com/apikey")!)
                .font(.caption)
        }

        if let statusMessage {
            Text(statusMessage)
                .font(.caption)
                .foregroundStyle(isError ? .red : .secondary)
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
