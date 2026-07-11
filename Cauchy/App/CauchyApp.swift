import SwiftUI

@main
struct CauchyApp: App {
    @State private var workspace = WorkspaceViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(workspace: workspace)
                .frame(minWidth: 1100, minHeight: 700)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open PDF…") {
                    workspace.openDocument()
                }
                .keyboardShortcut("o")
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
