import SwiftUI

struct HighlightThreadDetailView: View {
    @Bindable var workspace: WorkspaceViewModel
    var onBack: () -> Void

    @State private var question = ""

    private var thread: SelectionThread? {
        workspace.selectionThread.activeThread
    }

    var body: some View {
        ConversationPanel(
            selectedText: thread?.selectedText,
            messages: thread?.messages ?? [],
            streamingText: thread?.streamingAssistantText,
            isResponding: workspace.selectionThread.isResponding,
            isAskAvailable: workspace.readingAssistantAvailability.isAvailable,
            unavailabilityMessage: unavailabilityMessage,
            panelWidth: workspace.contextPanelWidth,
            question: $question,
            onSend: { sendQuestion() },
            onStop: {
                if let unanswered = workspace.stopThreadMessage() {
                    question = unanswered
                }
            },
            onModelChange: { workspace.refreshReadingAssistant() },
            header: { header }
        )
    }

    /// Floats over the conversation as a bar rather than sitting in a band
    /// above it. The bar carries the glass itself, like a toolbar does: the
    /// scroll edge effect obscures what passes underneath, but it is not a
    /// surface, and a title alone over an accent-coloured quote bubble is not
    /// readable. The back chevron is plain here for the same reason a
    /// navigation bar's is — the bar is the glass, and a capsule on top of it
    /// would be glass inside glass.
    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            // The thread's name, the same one the list shows — a header reading
            // "Highlight" told the reader nothing they didn't already know from
            // the tab above it.
            VStack(alignment: .leading, spacing: 1) {
                Text(headerTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let pageIndex = thread?.pageIndex {
                    Text("Page \(pageIndex + 1)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 6)

            if thread?.isPersisted == false {
                Button("Save as Highlight") {
                    workspace.saveTextSelectionAsHighlight()
                }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(in: .rect(cornerRadius: 18))
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    /// The saved thread's name when there is one; a draft selection has no
    /// highlight behind it yet, so it is named by its passage.
    private var headerTitle: String {
        guard let thread else { return "Highlight" }
        if let saved = workspace.highlightStore.highlights.first(where: { $0.id == thread.anchorID }) {
            return saved.displayName
        }
        return Highlight.title(from: thread.selectedText)
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
            return "\(provider.connector.name) is not set up. \(provider.connector.setupHint)"
        default:
            return "Ask is unavailable right now."
        }
    }

    private func sendQuestion() {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        workspace.sendThreadMessage(trimmed)
        question = ""
    }
}
