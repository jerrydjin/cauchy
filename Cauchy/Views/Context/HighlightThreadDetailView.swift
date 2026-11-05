import AppKit
import SwiftUI

struct HighlightThreadDetailView: View {
    @Bindable var workspace: WorkspaceViewModel
    var onBack: () -> Void

    @State private var question = ""
    @State private var setupConnector: AssistantConnectorID?

    private var thread: SelectionThread? {
        workspace.selectionThread.activeThread
    }

    private var ask: AskPresentation {
        AskPresentation.current()
    }

    var body: some View {
        GeometryReader { geometry in
            ConversationPanel(
                selectedText: thread?.selectedText,
                messages: thread?.messages ?? [],
                streamingText: thread?.streamingAssistantText,
                isResponding: workspace.selectionThread.isResponding,
                canAsk: ask.canAsk,
                unavailableMessage: ask.canAsk ? nil : ask.message,
                recoveryTitle: ask.canAsk ? nil : ask.buttonTitle,
                failureMessage: thread?.failureNotice,
                panelWidth: geometry.size.width,
                question: $question,
                onSend: { sendQuestion() },
                onStop: {
                    if let unanswered = workspace.stopThreadMessage() {
                        question = unanswered
                    }
                },
                onModelChange: { workspace.refreshReadingAssistant() },
                pinnedPassage: workspace.pinnedPassage,
                onOpenPassage: { workspace.openPinnedPassage() },
                onDismissPassage: { workspace.dismissPinnedPassage() },
                onRecovery: { performRecovery(ask.recovery) },
                onOpenSource: { workspace.goToAnswerSource($0) },
                referenceKeys: workspace.referenceIndex.referenceKeys,
                referenceIndexReady: !workspace.isIndexingReferences,
                onOpenReference: { workspace.openCitedReference($0) },
                followUpsFor: { workspace.suggestedFollowUps(for: $0) },
                onAskFollowUp: { workspace.sendThreadMessage($0) },
                header: { header }
            )
        }
        .task(id: ask.probeToken) {
            await ProviderReadinessStore.shared.probeIfNeededCurrentSelection()
        }
        .sheet(item: $setupConnector) { id in
            ConnectorSetupView(connector: id.connector) {
                workspace.refreshReadingAssistant()
            }
        }
    }

    private func performRecovery(_ recovery: AskRecovery?) {
        switch recovery {
        case .setup(let id):
            setupConnector = id
        case .settings:
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        case .retry(let id):
            let modelID = AssistantPreferences.modelChoice(for: id).modelID
            Task {
                await ProviderReadinessStore.shared.probe(connectorID: id, modelID: modelID, force: true)
            }
        case nil:
            break
        }
    }

    /// The glass belongs to the controls. The title band is the panel colour,
    /// not another glass slab: a clear band left the line under "Page" readable.
    private var header: some View {
        ConversationThreadHeader(
            title: headerTitle,
            pageNumber: thread.map { $0.pageIndex + 1 }
        ) {
            GlassIconButton(
                systemName: "chevron.left",
                accessibilityLabel: "Back",
                action: onBack
            )
        } trailing: {
            if let id = savedHighlightID, let highlight = savedHighlight {
                Menu {
                    HighlightColorMenu(current: highlight.color) { colour in
                        workspace.setColor(colour, for: id)
                    }
                    Divider()
                    Button("Copy as Markdown") {
                        workspace.copyThreadAsMarkdown(highlight)
                    }
                    Divider()
                    Button("Delete Highlight", role: .destructive) {
                        workspace.deleteHighlight(highlight)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 22)
                .accessibilityLabel("Highlight options")
            }

            if thread?.isPersisted == false {
                Button("Save as Highlight") {
                    workspace.saveTextSelectionAsHighlight()
                }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
            }
        }
    }

    /// The saved highlight this thread belongs to, if it has been saved at all.
    private var savedHighlight: Highlight? {
        guard let anchorID = thread?.anchorID else { return nil }
        return workspace.highlightStore.highlights.first { $0.id == anchorID }
    }

    private var savedHighlightID: UUID? { savedHighlight?.id }

    /// The saved thread's name when there is one; a draft selection has no
    /// highlight behind it yet, so it is named by its passage.
    private var headerTitle: String {
        guard let thread else { return "Highlight" }
        if let saved = workspace.highlightStore.highlights.first(where: { $0.id == thread.anchorID }) {
            return saved.displayName
        }
        return Highlight.title(from: thread.selectedText)
    }

    private func sendQuestion() {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        workspace.sendThreadMessage(trimmed)
        question = ""
    }
}
