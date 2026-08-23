import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted when Settings changes which model answers questions. Every open
    /// window has its own assistant, so this is a broadcast rather than a call.
    static let assistantPreferencesChanged = Notification.Name("CauchyAssistantPreferencesChanged")
}

@main
struct CauchyApp: App {
    /// True when the app was launched only to host a test bundle. The unit
    /// tests exercise pure logic, so a reader reopening yesterday's paper and
    /// starting an on-device index behind them is pure interference — enough
    /// of it that the test runner can time out waiting to connect.
    static let isHostingTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

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
        } else if !Self.isHostingTests {
            // Normal GUI launch: sweep reference-index caches that no document
            // has touched in months (content-hashed names are never reused).
            Task.detached(priority: .background) {
                ReferenceIndexCacheStore.pruneStaleCaches()
            }
        }
    }

    var body: some Scene {
        // Deliberately without an `id`: an identified WindowGroup presents no
        // window of its own at launch, so a first run — or any run after the
        // saved window state is cleared — came up with a menu bar and nothing
        // else. Unidentified, SwiftUI presents the first window and supplies
        // File ▸ New Window itself.
        WindowGroup {
            if Self.benchmarkConfig != nil {
                ProgressView("Running indexing benchmark — see terminal output…")
                    .padding(40)
            } else {
                ReaderWindow()
            }
        }
        .commands { ReaderCommands() }

        Settings {
            SettingsView {
                NotificationCenter.default.post(name: .assistantPreferencesChanged, object: nil)
            }
        }
    }
}

/// One window's worth of reader. The workspace lives here rather than on the
/// App so that a second window is a second document, not a second view of the
/// same one.
private struct ReaderWindow: View {
    @State private var workspace = WorkspaceViewModel()
    @Environment(\.undoManager) private var windowUndoManager

    /// Only the window the app launches with reopens the last document; a
    /// window the reader asked for is a window they want empty.
    @State private var didAttemptRestore = false

    var body: some View {
        ContentView(workspace: workspace)
            .frame(minWidth: 1100, minHeight: 700)
            .background(WindowAccessor { workspace.hostWindow = $0 })
            // Finder/dock open events (double-click, "Open With", dock
            // drops) arrive here; SwiftUI buffers ones that fire before
            // the scene connects. Deliberately the only open handler:
            // an NSApplicationDelegateAdaptor implementing
            // application(_:open:) would ALSO be called, double-opening
            // every file.
            .onOpenURL { url in
                guard url.isFileURL, url.pathExtension.lowercased() == "pdf" else { return }
                didAttemptRestore = true
                Task { await workspace.openDocument(at: url) }
            }
            .focusedSceneValue(\.readerWorkspace, workspace)
            .onChange(of: windowUndoManager, initial: true) {
                workspace.hostUndoManager = windowUndoManager
            }
            .onReceive(NotificationCenter.default.publisher(for: .assistantPreferencesChanged)) { _ in
                workspace.refreshReadingAssistant()
            }
            .task {
                guard !didAttemptRestore, Self.claimLaunchRestore() else { return }
                didAttemptRestore = true
                await workspace.restoreLastSession()
            }
    }

    @MainActor private static var launchRestoreClaimed = false

    /// True exactly once per launch, for whichever window comes up first.
    @MainActor private static func claimLaunchRestore() -> Bool {
        guard !launchRestoreClaimed else { return false }
        launchRestoreClaimed = true
        return true
    }
}
