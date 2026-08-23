import AppKit
import Foundation

/// Which document each open window is reading.
///
/// With one window per workspace, opening the same PDF twice would give it two
/// independent readers, both saving over the same `workspace.json` — the second
/// one to write wins, and whatever the reader did in the other window is gone.
/// So a document belongs to exactly one window, and a second attempt to open it
/// brings that window forward instead.
@MainActor
final class OpenDocumentRegistry {
    static let shared = OpenDocumentRegistry()

    private var holders: [String: WeakWorkspace] = [:]

    private struct WeakWorkspace {
        weak var workspace: WorkspaceViewModel?
    }

    private init() {}

    private func key(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    /// The window already reading this document, if there is one. Entries whose
    /// workspace has gone away are cleared as they are found — windows close
    /// without any single place to hook.
    func holder(of url: URL) -> WorkspaceViewModel? {
        let key = key(for: url)
        guard let entry = holders[key] else { return nil }
        guard let workspace = entry.workspace else {
            holders[key] = nil
            return nil
        }
        return workspace
    }

    func claim(_ url: URL, by workspace: WorkspaceViewModel) {
        release(by: workspace)
        holders[key(for: url)] = WeakWorkspace(workspace: workspace)
    }

    func release(by workspace: WorkspaceViewModel) {
        for (key, entry) in holders where entry.workspace === workspace {
            holders[key] = nil
        }
    }
}
