import SwiftUI

/// Lets the menu bar reach the reader in the frontmost window. With more than
/// one window open there is no single "the" workspace any more, so commands ask
/// for the focused one instead of closing over a shared instance.
struct ReaderWorkspaceFocusKey: FocusedValueKey {
    typealias Value = WorkspaceViewModel
}

struct LearningLibraryFocusKey: FocusedValueKey {
    typealias Value = LearningLibraryStore
}

extension FocusedValues {
    var learningLibrary: LearningLibraryStore? {
        get { self[LearningLibraryFocusKey.self] }
        set { self[LearningLibraryFocusKey.self] = newValue }
    }
    var readerWorkspace: WorkspaceViewModel? {
        get { self[ReaderWorkspaceFocusKey.self] }
        set { self[ReaderWorkspaceFocusKey.self] = newValue }
    }
}

struct ReaderCommands: Commands {
    @FocusedValue(\.readerWorkspace) private var workspace
    @FocusedValue(\.learningLibrary) private var learningLibrary
    @FocusedValue(\.planLearningSession) private var planLearningSession
    @Environment(\.openWindow) private var openWindow

    private var hasDocument: Bool { workspace?.pdfDocument != nil }

    var body: some Commands {
        // `after:` rather than `replacing:` — the WindowGroup's own New Window
        // item lives in this group, and it is the only way to read two papers
        // at once (a paper beside the one it cites, most of the time).
        CommandGroup(after: .newItem) {
            Button(learningLibrary == nil ? "Open PDF…" : "Open Notes…") {
                if let learningLibrary { learningLibrary.openNotes() } else { workspace?.openDocument() }
            }
            .keyboardShortcut("o")
            .disabled(workspace == nil && learningLibrary == nil)

            Button("Open Reading Session…") {
                workspace?.openReadingSession()
            }
            .disabled(workspace == nil)

            Button("Close Document") {
                workspace?.closeDocument()
            }
            .keyboardShortcut("w")
            .disabled(!hasDocument)
        }

        CommandGroup(after: .saveItem) {
            Button("Export Reading Session…") {
                workspace?.exportReadingSession()
            }
            .disabled(workspace?.canExportReadingSession != true)

            Divider()

            Button("Export Highlights as Markdown…") {
                workspace?.exportHighlightsAsMarkdown()
            }
            .disabled(workspace?.canExportHighlights != true)

            Button("Save a Copy with Highlights…") {
                workspace?.exportAnnotatedPDFCopy()
            }
            .disabled(workspace?.canExportHighlights != true)

            Button("Copy All Highlights as Markdown") {
                workspace?.copyHighlightsAsMarkdown()
            }
            .disabled(workspace?.canExportHighlights != true)

            Divider()
        }

        CommandGroup(replacing: .printItem) {
            Button("Print…") {
                workspace?.printDocument()
            }
            .keyboardShortcut("p")
            .disabled(!hasDocument)
        }

        // Replaces the default Edit ▸ Find submenu (part of the textEditing
        // group) so ⌘F reaches the PDF find bar instead of the responder chain.
        CommandGroup(replacing: .textEditing) {
            Button("Find…") {
                workspace?.presentFindBar()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(!hasDocument)

            Button("Find Next") {
                workspace?.find.findNext()
            }
            .keyboardShortcut("g", modifiers: .command)
            .disabled(workspace?.find.hasMatches != true)

            Button("Find Previous") {
                workspace?.find.findPrevious()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(workspace?.find.hasMatches != true)
        }

        CommandMenu("Learn") {
            Button("Open Learning Workspace") { showLearning() }
            .keyboardShortcut("l", modifiers: [.command, .shift])

            Button("Study This Passage…") { showLearning(newSection: true) }
            .disabled(!hasDocument)

            Button("Study a Passage") {
                guard let document = learningLibrary?.selectedDocument else { return }
                document.requestsNewSection = true
                document.learning.showSections()
                learningLibrary?.destination = .passage(document.id)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(learningLibrary?.selectedDocument == nil || learningLibrary?.selectedDocument?.isBusy == true)

            Divider()

            Button("Show Learning Path") { showLearningPath() }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(learningLibrary?.selectedDocument == nil || learningLibrary?.selectedDocument?.isBusy == true)

            Button("Plan a Study Session…") { planLearningSession?() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(planLearningSession == nil)

            Button(learningLibrary?.selectedDocument?.studyMap.currentStudyRun?.state == .paused ? "Resume Study Session" : "Pause Study Session") {
                guard let document = learningLibrary?.selectedDocument else { return }
                if document.studyMap.currentStudyRun?.state == .paused {
                    document.continueStudyRun()
                } else {
                    document.pauseStudyRun()
                    showLearningPath()
                }
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(!canToggleStudySession)

            Button("Finish Study Session Here") {
                learningLibrary?.selectedDocument?.finishStudyRun()
                showLearningPath()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(!hasStudySession || learningLibrary?.selectedDocument?.studyMap.isBusy == true)

            Divider()

            Button(learningLibrary?.selectedDocument?.notesVisible == true ? "Hide Source Notes" : "Show Source Notes") {
                guard let document = learningLibrary?.selectedDocument else { return }
                if document.notesVisible { document.notesVisible = false } else { document.showNotes() }
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(learningLibrary?.selectedDocument == nil)
        }

        CommandMenu("Reading") {
            Button(workspace?.contextPanelVisible == true ? "Hide Context Panel" : "Show Context Panel") {
                workspace?.toggleContextPanel()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(!hasDocument)

            Button("Zoom In") { workspace?.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(!hasDocument)

            Button("Zoom Out") { workspace?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!hasDocument)

            Button("Actual Size") { workspace?.zoomToActualSize() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(!hasDocument)

            Button("Fit to Width") { workspace?.zoomToFitWidth() }
                .disabled(!hasDocument)

            Divider()

            Toggle(
                "Select Region",
                isOn: Binding(
                    get: { workspace?.selectionModeActive ?? false },
                    set: { workspace?.selectionModeActive = $0 }
                )
            )
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(!hasDocument)

            Button("Highlight Selection") {
                workspace?.saveTextSelectionAsHighlight()
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])
            .disabled(workspace?.canSaveTextSelection != true)

            Divider()

            Button("Previous Page") { workspace?.goToPreviousPage() }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(!hasDocument)

            Button("Next Page") { workspace?.goToNextPage() }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(!hasDocument)

            Button("Go to Page…") { workspace?.presentGoToPagePanel() }
                .keyboardShortcut("g", modifiers: [.command, .option])
                .disabled(!hasDocument)

            Button("Back") { workspace?.goBack() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!hasDocument)

            Button("Forward") { workspace?.goForward() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!hasDocument)

            Divider()

            Toggle(
                "Invert Page Colors",
                isOn: Binding(
                    get: { workspace?.invertPageColors ?? false },
                    set: { workspace?.invertPageColors = $0 }
                )
            )
            .disabled(!hasDocument)

            Divider()

            Menu("Rebuild Reference Index") {
                if let workspace {
                    ReferenceIndexMenuItems(workspace: workspace)
                }
            }
            .disabled(!hasDocument)

            Button("Reset All Reference Indexes…") {
                workspace?.resetAllReferenceIndexes()
            }
            .disabled(workspace == nil || workspace?.isIndexingReferences == true)

            Divider()

            Button("Copy LaTeX") {
                workspace?.copyLatexToClipboard()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(workspace?.ocrResult == nil)
        }
    }

    private var hasStudySession: Bool {
        guard let run = learningLibrary?.selectedDocument?.studyMap.currentStudyRun else { return false }
        return run.state != .finished
    }

    private var canToggleStudySession: Bool {
        guard let document = learningLibrary?.selectedDocument,
              let run = document.studyMap.currentStudyRun, run.state != .finished else { return false }
        // Pause retains the toolbar's ability to cancel an in-flight tutor.
        return run.state == .paused ? !document.isBusy : !document.studyMap.isBusy
    }

    private func showLearningPath() {
        guard let library = learningLibrary, let document = library.selectedDocument else { return }
        Task { await library.navigate(to: .studyMap(document.id)) }
    }

    private func showLearning(newSection: Bool = false) {
        if CauchyApp.learningUIFixtureRequested {
            openWindow(id: "learning")
            return
        }
        // Opening the workspace resumes its own context. Only the explicit
        // section action adopts the reader's current document and selection.
        if newSection, let workspace, hasDocument {
            LearningLibraryStore.shared.activate(from: workspace, newSection: true)
        }
        openWindow(id: "learning")
        Task { await LearningLibraryStore.shared.refreshLibrary() }
    }
}
