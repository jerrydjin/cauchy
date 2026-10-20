import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct HighlightThreadDetailView: View {
    @Bindable var workspace: WorkspaceViewModel
    @Environment(\.openWindow) private var openWindow
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
                selectedText: nil,
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
                onRecovery: { performRecovery(ask.recovery) },
                onOpenSource: { workspace.goToAnswerSource($0) },
                highlightTag: workspace.attachedHighlight?.tagTitle,
                sheetTag: workspace.problemSheet?.tagTitle,
                onRemoveHighlight: { workspace.removeHighlightTag() },
                onRemoveSheet: { workspace.removeProblemSheet() },
                onAttach: { workspace.showsAttachmentImporter = true },
                onDropProviders: { workspace.attachProblemSheet(from: $0) },
                referenceKeys: workspace.referenceIndex.referenceKeys,
                referenceBlock: { workspace.referenceIndex.block(for: $0) },
                onOpenReference: { workspace.openCitedReference($0) },
                onHoverReference: { workspace.previewCitedReference($0) },
                emptyPrompt: workspace.attachedHighlight == nil
                    ? "Ask a question about this document"
                    : "Ask a question about this passage",
                header: { header }
            )
            .fileImporter(
                isPresented: $workspace.showsAttachmentImporter,
                allowedContentTypes: [.pdf, .image],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    workspace.attachProblemSheet(at: url)
                }
            }
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

    /// Floats over the conversation. Nothing here is a surface: the glass
    /// belongs to the controls — the back button and, when it is there, the
    /// save button — while the title simply lies over the progressive blur the
    /// scroll edge effect draws where the messages pass underneath. A glass
    /// slab behind the whole row reads as one enormous button, which is both
    /// wrong and a lie about what is clickable.
    private var header: some View {
        headerRow
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            GlassIconButton(
                systemName: "chevron.left",
                accessibilityLabel: "Back",
                action: onBack
            )

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
            // A label, not a control. Without this the row's empty space is
            // still a hit target and the header behaves like one wide button.
            .allowsHitTesting(false)

            Spacer(minLength: 6)

            if thread?.messages.isEmpty == false {
                Button("New", action: { workspace.startNewConversation() })
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Start a new conversation")
                    .accessibilityLabel("New conversation")
            }

            if let id = savedHighlightID, let highlight = savedHighlight {
                Menu {
                    Button("Learn This Section…") {
                        LearningLibraryStore.shared.activate(from: workspace, newSection: true)
                        openWindow(id: "learning")
                        Task { await LearningLibraryStore.shared.refreshLibrary() }
                    }
                    Divider()
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

/// Whole-document chat in the same panel. The ask box stays at the bottom;
/// a highlight or problem sheet, when present, is a tag on that box.
struct DocumentConversationView: View {
    @Bindable var workspace: WorkspaceViewModel
    @State private var question = ""
    @State private var setupConnector: AssistantConnectorID?
    private var ask: AskPresentation { AskPresentation.current() }

    private var thread: SelectionThread? {
        workspace.selectionThread.activeThread
    }

    var body: some View {
        GeometryReader { geometry in
            ConversationPanel(
                selectedText: nil,
                messages: thread?.messages ?? [],
                streamingText: thread?.streamingAssistantText,
                isResponding: workspace.selectionThread.isResponding,
                canAsk: ask.canAsk,
                unavailableMessage: ask.canAsk ? nil : ask.message,
                recoveryTitle: ask.canAsk ? nil : ask.buttonTitle,
                failureMessage: thread?.failureNotice,
                panelWidth: geometry.size.width,
                question: $question,
                onSend: send,
                onStop: {
                    if let unanswered = workspace.stopThreadMessage() {
                        question = unanswered
                    }
                },
                onModelChange: { workspace.refreshReadingAssistant() },
                onRecovery: { performRecovery(ask.recovery) },
                onOpenSource: { workspace.goToAnswerSource($0) },
                highlightTag: workspace.attachedHighlight?.tagTitle,
                sheetTag: workspace.problemSheet?.tagTitle,
                onRemoveHighlight: { workspace.removeHighlightTag() },
                onRemoveSheet: { workspace.removeProblemSheet() },
                onAttach: { workspace.showsAttachmentImporter = true },
                onDropProviders: { workspace.attachProblemSheet(from: $0) },
                referenceKeys: workspace.referenceIndex.referenceKeys,
                referenceBlock: { workspace.referenceIndex.block(for: $0) },
                onOpenReference: { workspace.openCitedReference($0) },
                onHoverReference: { workspace.previewCitedReference($0) },
                emptyPrompt: "Ask a question about this document",
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
        .fileImporter(
            isPresented: $workspace.showsAttachmentImporter,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                workspace.attachProblemSheet(at: url)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            GlassIconButton(
                systemName: "chevron.left",
                accessibilityLabel: "Back",
                action: { workspace.showHighlightList() }
            )
            Text("Conversation")
                .font(.headline)
                .allowsHitTesting(false)
            Spacer(minLength: 6)
            if thread?.messages.isEmpty == false {
                Button("New", action: { workspace.startNewConversation() })
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Start a new conversation")
                    .accessibilityLabel("New conversation")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
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

    private func send() {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        workspace.sendThreadMessage(trimmed)
        question = ""
    }
}
