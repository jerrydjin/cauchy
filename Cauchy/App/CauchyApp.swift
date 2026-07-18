import SwiftUI

@main
struct CauchyApp: App {
    @State private var workspace = WorkspaceViewModel()

    /// Non-nil when launched headlessly as `Cauchy --benchmark-indexing …`.
    private static let benchmarkConfig = ReferenceIndexBenchmark.Config(arguments: CommandLine.arguments)

    init() {
        if let config = Self.benchmarkConfig {
            Task.detached {
                let code = await ReferenceIndexBenchmark.run(config: config)
                exit(code)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            if Self.benchmarkConfig != nil {
                ProgressView("Running indexing benchmark — see terminal output…")
                    .padding(40)
            } else {
                ContentView(workspace: workspace)
                    .frame(minWidth: 1100, minHeight: 700)
            }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open PDF…") {
                    workspace.openDocument()
                }
                .keyboardShortcut("o")
            }

            // Replaces the default Edit ▸ Find submenu (part of the textEditing
            // group) so ⌘F reaches the PDF find bar instead of the responder chain.
            CommandGroup(replacing: .textEditing) {
                Button("Find…") {
                    workspace.presentFindBar()
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(workspace.pdfDocument == nil)

                Button("Find Next") {
                    workspace.find.findNext()
                }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(!workspace.find.hasMatches)

                Button("Find Previous") {
                    workspace.find.findPrevious()
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(!workspace.find.hasMatches)
            }

            CommandMenu("Reading") {
                Button("Zoom In") {
                    workspace.zoomIn()
                }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(workspace.pdfDocument == nil)

                Button("Zoom Out") {
                    workspace.zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(workspace.pdfDocument == nil)

                Button("Actual Size") {
                    workspace.zoomToActualSize()
                }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(workspace.pdfDocument == nil)

                Button("Fit to Width") {
                    workspace.zoomToFitWidth()
                }
                .disabled(workspace.pdfDocument == nil)

                Divider()

                Toggle("Select Region", isOn: $workspace.selectionModeActive)
                    .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("Highlight Selection") {
                    workspace.saveTextSelectionAsHighlight()
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(workspace.selectionThread.activeThread == nil || workspace.selectionThread.activeThread?.isPersisted == true)

                Divider()

                Button("Previous Page") {
                    workspace.goToPreviousPage()
                }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(workspace.pdfDocument == nil)

                Button("Next Page") {
                    workspace.goToNextPage()
                }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(workspace.pdfDocument == nil)

                Button("Go to Page…") {
                    workspace.presentGoToPagePanel()
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(workspace.pdfDocument == nil)

                Divider()

                Button("Copy LaTeX") {
                    workspace.copyLatexToClipboard()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(workspace.ocrResult == nil)
            }
        }

        Settings {
            SettingsView {
                workspace.refreshReadingAssistant()
            }
        }
    }
}
