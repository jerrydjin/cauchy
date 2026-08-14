import SwiftUI

struct SettingsView: View {
    var onSettingsChanged: (() -> Void)?

    /// Typed-but-unsaved key text, per provider. Cleared the moment a key is
    /// committed to the Keychain — the app never keeps a secret in view state
    /// longer than the user is typing it.
    @State private var draftKeys: [CloudAPIProvider: String] = [:]
    @State private var storedKeys: Set<CloudAPIProvider> = Set(
        CloudAPIProvider.allCases.filter(KeychainService.hasKey(for:))
    )
    /// Only one key row is open at a time: the section is a list of vendors,
    /// not a form, and an accordion keeps the window from growing past its frame.
    @State private var expandedProvider: CloudAPIProvider?
    @State private var status: (provider: CloudAPIProvider, message: String, isError: Bool)?
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
                ForEach(CloudAPIProvider.allCases) { provider in
                    keyRow(provider)
                }
            } header: {
                Text("Your API keys")
            } footer: {
                Text("Bring your own key to reach a vendor's API directly. Keys are stored in your Keychain, sent only to the vendor they belong to, and billed to you per request. A saved key is also the fallback for reference indexing when Apple Intelligence is unavailable.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 560)
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

    // MARK: - API keys

    @ViewBuilder
    private func keyRow(_ provider: CloudAPIProvider) -> some View {
        DisclosureGroup(isExpanded: expansionBinding(for: provider)) {
            VStack(alignment: .leading, spacing: 10) {
                keyControls(provider)
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: provider.symbol)
                    .frame(width: 16)
                Text(provider.name)
                Spacer()
                if storedKeys.contains(provider) {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .labelStyle(.titleAndIcon)
                }
            }
            .font(.callout)
        }
    }

    @ViewBuilder
    private func keyControls(_ provider: CloudAPIProvider) -> some View {
        let draft = draftKeys[provider] ?? ""

        // The hint has to ride `prompt`, not the title: a Form turns a field's
        // title into a left column label, and hiding that label takes the hint
        // with it. As a prompt it sits inside the field, showing the shape of
        // the key the user is about to paste.
        SecureField(text: draftBinding(for: provider), prompt: Text(provider.keyPrefixHint)) {
            Text("\(provider.vendor) API key")
        }
        .textFieldStyle(.roundedBorder)
        .labelsHidden()

        HStack {
            Button("Save") {
                save(provider)
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Clear", role: .destructive) {
                clear(provider)
            }
            .disabled(!storedKeys.contains(provider))

            Spacer()

            Link("Get a key", destination: provider.consoleURL)
                .font(.caption)
        }

        if let status, status.provider == provider {
            Text(status.message)
                .font(.caption)
                .foregroundStyle(status.isError ? .red : .secondary)
        }
    }

    private func expansionBinding(for provider: CloudAPIProvider) -> Binding<Bool> {
        Binding {
            expandedProvider == provider
        } set: { isExpanded in
            expandedProvider = isExpanded ? provider : nil
        }
    }

    private func draftBinding(for provider: CloudAPIProvider) -> Binding<String> {
        Binding {
            draftKeys[provider] ?? ""
        } set: { newValue in
            draftKeys[provider] = newValue
        }
    }

    private func save(_ provider: CloudAPIProvider) {
        do {
            try KeychainService.saveKey(draftKeys[provider] ?? "", for: provider)
            draftKeys[provider] = ""
            storedKeys.insert(provider)
            status = (provider, "\(provider.vendor) API key saved.", false)
            onSettingsChanged?()
        } catch {
            status = (provider, error.localizedDescription, true)
        }
    }

    private func clear(_ provider: CloudAPIProvider) {
        do {
            try KeychainService.deleteKey(for: provider)
            draftKeys[provider] = ""
            storedKeys.remove(provider)
            status = (provider, "\(provider.vendor) API key removed.", false)
            onSettingsChanged?()
        } catch {
            status = (provider, error.localizedDescription, true)
        }
    }
}
