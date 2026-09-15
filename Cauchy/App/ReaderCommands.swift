import SwiftUI

/// Lets the menu bar reach the reader in the frontmost window. With more than
/// one window open there is no single "the" workspace any more, so commands ask
/// for the focused one instead of closing over a shared instance.
struct ReaderWorkspaceFocusKey: FocusedValueKey {
    typealias Value = WorkspaceViewModel
}

extension FocusedValues {
    var readerWorkspace: WorkspaceViewModel? {
        get { self[ReaderWorkspaceFocusKey.self] }
        set { self[ReaderWorkspaceFocusKey.self] = newValue }
    }
}

struct ReaderCommands: Commands {
    @FocusedValue(\.readerWorkspace) private var workspace

    private var hasDocument: Bool { workspace?.pdfDocument != nil }

    var body: some Commands {
        // `after:` rather than `replacing:` — the WindowGroup's own New Window
        // item lives in this group, and it is the only way to read two papers
        // at once (a paper beside the one it cites, most of the time).
        CommandGroup(after: .newItem) {
            Button("Open PDF…") {
                workspace?.openDocument()
            }
            .keyboardShortcut("o")
            .disabled(workspace == nil)

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

            Button("Rebuild Reference Index") {
                workspace?.rebuildReferenceIndex()
            }
            .disabled(!hasDocument || workspace?.isIndexingReferences == true)

            // Not gated on isIndexingReferences: switching to the cloud
            // part-way through a slow on-device build is the main reason to
            // reach for this, and rebuilding cancels the in-flight task first.
            Button("Re-index with \(workspace?.cloudReindexVendor ?? "Cloud")") {
                workspace?.rebuildReferenceIndex(usingCloud: true)
            }
            .disabled(!hasDocument || workspace?.canRebuildReferenceIndexWithCloud != true)

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
}
