import SwiftUI

struct HighlightThreadDetailView: View {
    @Bindable var workspace: WorkspaceViewModel
    let title: String
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

                Text(title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()
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
                onSend: { Task { await sendQuestion() } }
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
