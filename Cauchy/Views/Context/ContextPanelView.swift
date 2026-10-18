import SwiftUI
import UniformTypeIdentifiers

struct ContextPanelView: View {
    @Bindable var workspace: WorkspaceViewModel

    var body: some View {
        VStack(spacing: 0) {
            ContextTabPicker(
                selection: $workspace.contextEngine.selectedTab,
                options: [
                    (.highlights, "Highlights"),
                    (.reference, "Reference"),
                ]
            )
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Group {
                switch workspace.contextEngine.selectedTab {
                case .highlights:
                    highlightsContent
                case .reference:
                    ReferencePreviewView(workspace: workspace)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var highlightsContent: some View {
        switch workspace.contextEngine.route {
        case .list where workspace.contextEngine.showsDocumentConversation:
            DocumentConversationView(workspace: workspace)
        case .list:
            VStack(spacing: 0) {
                if !workspace.selectionThread.documentThread.messages.isEmpty {
                    Button("Conversation", systemImage: "text.bubble") {
                        workspace.showDocumentConversation()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                }
                HighlightListView(workspace: workspace)
                listAskBox
            }
        case .detail(let id):
            if workspace.highlightStore.highlights.contains(where: { $0.id == id }) {
                HighlightThreadDetailView(
                    workspace: workspace,
                    onBack: { workspace.showHighlightList() }
                )
            } else {
                HighlightListView(workspace: workspace)
                    .onAppear { workspace.showHighlightList() }
            }
        case .composeDraft:
            HighlightThreadDetailView(
                workspace: workspace,
                onBack: { workspace.showHighlightList() }
            )
        }
    }

    /// The ask box stays at the bottom of the list, usable with no highlight.
    private var listAskBox: some View {
        ListAskBox(workspace: workspace)
    }
}

/// Ask box under the highlight list. Sending with no tag opens the document
/// conversation in this same panel.
private struct ListAskBox: View {
    @Bindable var workspace: WorkspaceViewModel
    @State private var question = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !workspace.readingAssistantAvailability.isAvailable {
                Text(AskAvailabilityMessage.text(for: workspace.readingAssistantAvailability))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ConversationComposer(
                question: $question,
                isResponding: workspace.selectionThread.isResponding,
                isEnabled: workspace.readingAssistantAvailability.isAvailable,
                highlightTag: workspace.attachedHighlight?.tagTitle,
                sheetTag: workspace.problemSheet?.tagTitle,
                onSend: send,
                onStop: {
                    if let unanswered = workspace.stopThreadMessage() {
                        question = unanswered
                    }
                },
                onModelChange: { workspace.refreshReadingAssistant() },
                onRemoveHighlight: { workspace.removeHighlightTag() },
                onRemoveSheet: { workspace.removeProblemSheet() },
                onAttach: { workspace.showsAttachmentImporter = true },
                onDropProviders: { workspace.attachProblemSheet(from: $0) }
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .fileImporter(
            isPresented: $workspace.showsAttachmentImporter,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let url) = result {
                workspace.attachProblemSheet(at: url)
            }
        }
    }

    private func send() {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        workspace.sendThreadMessage(trimmed)
        question = ""
    }
}
