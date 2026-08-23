import XCTest
@testable import Cauchy

@MainActor
final class WorkspaceUndoTests: XCTestCase {
    /// No window, so the workspace falls back to its own undo manager — which
    /// is the same object the menu drives when a window has handed one down.
    private func makeWorkspace(with highlights: [Highlight]) -> WorkspaceViewModel {
        let workspace = WorkspaceViewModel()
        workspace.highlightStore.highlights = highlights
        return workspace
    }

    private func makeHighlight(text: String = "a passage") -> Highlight {
        Highlight(pageIndex: 1, selectedText: text)
    }

    /// UndoManager coalesces everything registered within one event into a
    /// single step. In the app successive edits arrive in separate events; in a
    /// test they all land in the same one, so the grouping is driven by hand
    /// instead of by run-loop timing.
    private func asSeparateEdits(_ manager: UndoManager, _ edits: [() -> Void]) {
        manager.groupsByEvent = false
        for edit in edits {
            manager.beginUndoGrouping()
            edit()
            manager.endUndoGrouping()
        }
    }

    func testDeletingAHighlightIsUndoable() {
        let highlight = makeHighlight()
        let workspace = makeWorkspace(with: [highlight])

        workspace.deleteHighlight(highlight, confirm: false)
        XCTAssertTrue(workspace.highlightStore.highlights.isEmpty)

        workspace.undoManager.undo()

        XCTAssertEqual(workspace.highlightStore.highlights.count, 1)
        XCTAssertEqual(workspace.highlightStore.highlights.first?.id, highlight.id)
    }

    /// The conversation is the part worth protecting — a restored highlight
    /// with an empty thread would be the same loss in a different shape.
    func testUndoRestoresTheConversationToo() {
        var highlight = makeHighlight()
        highlight.messages = [
            ThreadMessage(role: .user, content: "why?"),
            ThreadMessage(role: .assistant, content: "because."),
        ]
        let workspace = makeWorkspace(with: [highlight])

        workspace.deleteHighlight(highlight, confirm: false)
        workspace.undoManager.undo()

        XCTAssertEqual(workspace.highlightStore.highlights.first?.messages.count, 2)
        XCTAssertEqual(workspace.highlightStore.highlights.first?.messages.last?.content, "because.")
    }

    func testDeleteCanBeRedone() {
        let highlight = makeHighlight()
        let workspace = makeWorkspace(with: [highlight])

        workspace.deleteHighlight(highlight, confirm: false)
        workspace.undoManager.undo()
        workspace.undoManager.redo()

        XCTAssertTrue(workspace.highlightStore.highlights.isEmpty)
    }

    func testEditingANoteIsUndoable() {
        let highlight = makeHighlight()
        let workspace = makeWorkspace(with: [highlight])

        asSeparateEdits(workspace.undoManager, [
            { workspace.setNote("first thought", for: highlight.id) },
            { workspace.setNote("second thought", for: highlight.id) },
        ])
        XCTAssertEqual(workspace.highlightStore.highlights.first?.note, "second thought")

        workspace.undoManager.undo()

        XCTAssertEqual(workspace.highlightStore.highlights.first?.note, "first thought")
    }

    func testBlankNoteIsStoredAsNothing() {
        let highlight = makeHighlight()
        let workspace = makeWorkspace(with: [highlight])

        workspace.setNote("   \n ", for: highlight.id)

        XCTAssertNil(workspace.highlightStore.highlights.first?.note)
    }

    func testRecolouringIsUndoable() {
        let highlight = makeHighlight()
        let workspace = makeWorkspace(with: [highlight])

        workspace.setColor(.blue, for: highlight.id)
        XCTAssertEqual(workspace.highlightStore.highlights.first?.color, .blue)

        workspace.undoManager.undo()

        XCTAssertEqual(workspace.highlightStore.highlights.first?.color, .yellow)
    }

    /// Undo steps close over a specific document's highlights; carrying them
    /// into the next document would re-add a highlight where it never existed.
    func testClosingADocumentClearsTheUndoStack() {
        let highlight = makeHighlight()
        let workspace = makeWorkspace(with: [highlight])

        workspace.deleteHighlight(highlight, confirm: false)
        XCTAssertTrue(workspace.undoManager.canUndo)

        workspace.closeDocument()

        XCTAssertFalse(workspace.undoManager.canUndo)
    }
}
