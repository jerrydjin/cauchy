import SwiftUI

struct HighlightThreadDetailView: View {
    @Bindable var workspace: WorkspaceViewModel
    var onBack: () -> Void

    @State private var question = ""

    private var thread: SelectionThread? {
        workspace.selectionThread.activeThread
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                GlassIconButton(
                    systemName: "chevron.left",
                    accessibilityLabel: "Back",
                    action: onBack
                )

                Text("Highlight")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()
                
                if thread?.isPersisted == false {
                    Button("Save as Highlight") {
                        workspace.saveTextSelectionAsHighlight()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ConversationPanel(
                selectedText: thread?.selectedText,
                messages: thread?.messages ?? [],
                streamingText: thread?.streamingAssistantText,
                isResponding: workspace.selectionThread.isResponding,
                isAskAvailable: workspace.readingAssistantAvailability.isAvailable,
                unavailabilityMessage: unavailabilityMessage,
                panelWidth: workspace.contextPanelWidth,
                question: $question,
                onSend: { Task { await sendQuestion() } },
                onModelChange: { workspace.refreshReadingAssistant() }
            )
            .padding(16)
        }
    }

    private var unavailabilityMessage: String? {
        guard !workspace.readingAssistantAvailability.isAvailable else { return nil }
        switch workspace.readingAssistantAvailability {
        case .deviceNotEligible:
            return "Apple Intelligence is not supported on this Mac."
        case .intelligenceNotEnabled:
            return "Enable Apple Intelligence in System Settings to ask questions."
        case .modelNotReady:
            return "The on-device model is downloading. Try again soon."
        case .geminiKeyMissing:
            return "Add a Gemini API key in Settings to ask questions."
        case .cliNotInstalled(let provider):
            return "\(provider.cliDisplayName) CLI not found. Install it and sign in, then try again."
        default:
            return "Ask is unavailable right now."
        }
    }

    private func sendQuestion() async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await workspace.sendThreadMessage(trimmed)
        question = ""
    }
}
