import XCTest
import PDFKit
import AppKit
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

@MainActor
final class WorkspacePersistenceTests: XCTestCase {
    func testDebouncedSavesKeepBothDocumentsAndLatestRevision() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = DocumentPersistenceService(root: root)
        var first = DocumentWorkspace(documentURL: URL(fileURLWithPath: "/tmp/first.pdf"))
        let second = DocumentWorkspace(documentURL: URL(fileURLWithPath: "/tmp/second.pdf"))
        persistence.scheduleSave(first, bookmarkData: nil)
        persistence.scheduleSave(second, bookmarkData: nil)
        first.highlights = [Highlight(pageIndex: 0, selectedText: "A saved theorem")]
        persistence.scheduleSave(first, bookmarkData: nil)
        try await Task.sleep(for: .seconds(0.8))
        let reader = DocumentPersistenceService(root: root)
        let savedFirst = await reader.loadWorkspace(id: first.id)
        let savedSecond = await reader.loadWorkspace(id: second.id)
        XCTAssertEqual(savedFirst?.workspace.highlights.first?.selectedText, "A saved theorem")
        XCTAssertEqual(savedSecond?.workspace.id, second.id)
    }

    func testImmediateFlushIncludesSynchronouslyEnqueuedSaves() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = DocumentPersistenceService(root: root)
        let workspace = DocumentWorkspace(documentURL: URL(fileURLWithPath: "/tmp/paper.pdf"))
        persistence.scheduleSave(workspace, bookmarkData: nil)
        try await persistence.flushAll()
        let reader = DocumentPersistenceService(root: root)
        let saved = await reader.loadWorkspace(id: workspace.id)
        XCTAssertEqual(saved?.workspace.id, workspace.id)
    }

    func testFailedFlushRetainsChangesForRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("blocked".utf8).write(to: root)
        let persistence = DocumentPersistenceService(root: root)
        let workspace = DocumentWorkspace(documentURL: URL(fileURLWithPath: "/tmp/paper.pdf"))
        persistence.scheduleSave(workspace, bookmarkData: nil)
        do {
            try await persistence.flushAll()
            XCTFail("Writing into a file should fail")
        } catch {}
        try FileManager.default.removeItem(at: root)
        try await persistence.flushAll()
        let reader = DocumentPersistenceService(root: root)
        let saved = await reader.loadWorkspace(id: workspace.id)
        XCTAssertEqual(saved?.workspace.id, workspace.id)
    }

    func testImportReadingSessionCreatesManagedIndependentWorkspace() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.pdf")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("test-pdf".utf8).write(to: source)
        var exported = DocumentWorkspace(documentURL: source)
        exported.primaryViewport.pageIndex = 8
        exported.highlights = [Highlight(pageIndex: 4, selectedText: "carry me")]
        let originalID = exported.id
        let packageURL = root.appendingPathComponent("handoff.cauchyreading", isDirectory: true)
        try ReadingSessionPackageService.write(
            sourcePDF: source,
            destination: packageURL,
            workspace: exported
        )

        let persistence = DocumentPersistenceService(root: root.appendingPathComponent("library"))
        let imported = try await persistence.importReadingSession(from: packageURL)

        XCTAssertNotEqual(imported.workspace.id, originalID)
        XCTAssertEqual(imported.workspace.primaryViewport.pageIndex, 8)
        XCTAssertEqual(imported.workspace.highlights.first?.selectedText, "carry me")
        XCTAssertEqual(imported.workspace.documentURL.lastPathComponent, "source.pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.workspace.documentURL.path))
    }
}

@MainActor
final class WorkspaceReopenTests: XCTestCase {
    func testReopenBeforeDebounceReturnsLatestNotes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = DocumentPersistenceService(root: root)
        var workspace = DocumentWorkspace(documentURL: URL(fileURLWithPath: "/tmp/paper.pdf"))
        try await persistence.saveWorkspace(workspace, bookmarkData: nil)
        workspace.highlights = [Highlight(pageIndex: 0, selectedText: "Latest passage")]
        persistence.scheduleSave(workspace, bookmarkData: nil)
        let reopened = try await persistence.loadWorkspace(for: workspace.documentURL)
        XCTAssertEqual(reopened?.workspace.highlights.first?.selectedText, "Latest passage")
    }
}

@MainActor
final class ReadingLayoutTests: XCTestCase {
    func testFitToWidthFollowsReaderResize() throws {
        let image = NSImage(size: NSSize(width: 600, height: 800), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            return true
        }
        let document = PDFDocument()
        document.insert(try XCTUnwrap(PDFPage(image: image)), at: 0)
        let view = PDFView(frame: NSRect(x: 0, y: 0, width: 600, height: 800))
        view.document = document
        let controller = PDFViewportController(role: .primary)
        controller.attach(to: view)
        var state = ViewportState.default
        state.scaleFactor = -1
        controller.apply(state: state, animated: false)
        let initialScale = view.scaleFactor
        view.frame.size.width = 300
        controller.applyFitToWidthIfNeeded()
        XCTAssertEqual(view.scaleFactor, initialScale / 2, accuracy: 0.01)
    }

    func testExplicitZoomIsPreservedWhenReaderResizes() throws {
        let image = NSImage(size: NSSize(width: 600, height: 800), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            return true
        }
        let document = PDFDocument()
        document.insert(try XCTUnwrap(PDFPage(image: image)), at: 0)
        let view = PDFView(frame: NSRect(x: 0, y: 0, width: 600, height: 800))
        view.document = document
        let controller = PDFViewportController(role: .primary)
        controller.attach(to: view)
        var state = ViewportState.default
        state.scaleFactor = 1.5
        controller.apply(state: state, animated: false)
        view.frame.size.width = 300
        controller.applyFitToWidthIfNeeded()
        XCTAssertEqual(view.scaleFactor, 1.5, accuracy: 0.01)
    }
}
