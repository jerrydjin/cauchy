import AppKit
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
        } else if let flagIndex = CommandLine.arguments.firstIndex(of: "--probe-retrieval"),
                  CommandLine.arguments.indices.contains(flagIndex + 2) {
            let pdfPath = CommandLine.arguments[flagIndex + 1]
            let query = CommandLine.arguments[flagIndex + 2]
            Task.detached {
                exit(await ReferenceIndexBenchmark.runRetrievalProbe(pdfPath: pdfPath, query: query))
            }
        } else {
            // Normal GUI launch: sweep reference-index caches that no document
            // has touched in months (content-hashed names are never reused).
            Task.detached(priority: .background) {
                ReferenceIndexCacheStore.pruneStaleCaches()
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
                    // Finder/dock open events (double-click, "Open With", dock
                    // drops) arrive here; SwiftUI buffers ones that fire before
                    // the scene connects. Deliberately the only open handler:
                    // an NSApplicationDelegateAdaptor implementing
                    // application(_:open:) would ALSO be called, double-opening
                    // every file.
                    .onOpenURL { url in
                        guard url.isFileURL, url.pathExtension.lowercased() == "pdf" else { return }
                        Task { await workspace.openDocument(at: url) }
                    }
            }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open PDF…") {
                    workspace.openDocument()
                }
                .keyboardShortcut("o")

                Button("Close Document") {
                    workspace.closeDocument()
                }
                .keyboardShortcut("w")
                .disabled(workspace.pdfDocument == nil)
            }

            CommandGroup(replacing: .printItem) {
                Button("Print…") {
                    workspace.printDocument()
                }
                .keyboardShortcut("p")
                .disabled(workspace.pdfDocument == nil)
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
                .keyboardShortcut("g", modifiers: [.command, .option])
                .disabled(workspace.pdfDocument == nil)

                Button("Back") {
                    workspace.goBack()
                }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(workspace.pdfDocument == nil)

                Button("Forward") {
                    workspace.goForward()
                }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(workspace.pdfDocument == nil)

                Divider()

                Toggle("Invert Page Colors", isOn: $workspace.invertPageColors)
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
