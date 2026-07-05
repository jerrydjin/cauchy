import SwiftUI

struct SettingsView: View {
    var onSettingsChanged: (() -> Void)?

    @State private var apiKey = ""
    @State private var hasStoredKey = KeychainService.hasGeminiAPIKey
    @State private var statusMessage: String?
    @State private var isError = false

    init(onSettingsChanged: (() -> Void)? = nil) {
        self.onSettingsChanged = onSettingsChanged
    }

    var body: some View {
        Form {
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
                Text("Cloud Model")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("When a Gemini API key is saved, Ask uses Google Gemini in the cloud. Otherwise, Ask uses on-device Apple Intelligence.")
                    Link("Get a Gemini API key", destination: URL(string: "https://aistudio.google.com/apikey")!)
                }
            }

            Section("Active Provider") {
                if hasStoredKey {
                    Label("Gemini (cloud)", systemImage: "cloud")
                } else {
                    Label("Apple Intelligence (on-device)", systemImage: "apple.logo")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 320)
        .padding()
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
