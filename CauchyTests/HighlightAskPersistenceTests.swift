import XCTest
@testable import Cauchy

/// The highlight is written when the question is sent. A failure keeps it,
/// and reopening the thread while the answer is still arriving keeps the
/// text that is already on screen.
@MainActor
final class HighlightAskPersistenceTests: XCTestCase {
    func testQuestionIsSavedBeforeTheAskAndAFailureKeepsTheHighlight() async throws {
        let model = WorkspaceViewModel()
        model.workspace = DocumentWorkspace(documentURL: URL(fileURLWithPath: "/tmp/jerry-155.pdf"))
        let assistant = ScriptedReadingAssistant()
        model.selectionThread = SelectionThreadViewModel(assistant: assistant)
        let anchor = UUID()
        model.selectionThread.activeThread = SelectionThread(
            anchorID: anchor,
            pageIndex: 81,
            selectedText: "Suppose h(z0) = h'(z0) = 0.",
            surroundingText: "Suppose h(z0) = h'(z0) = 0. Then a0 = a1 = 0."
        )

        assistant.script = { question, _ in
            let saved = model.highlightStore.highlights
            XCTAssertEqual(saved.map(\.id), [anchor])
            XCTAssertEqual(saved.first?.messages.map(\.content), [question])
            XCTAssertNil(saved.first?.askFailure)
            throw StubAskFailure()
        }

        model.sendThreadMessage("Why is a0 zero?")
        let failed = try await waitHighlight(model)
        XCTAssertEqual(failed.askFailure, "The model stopped.")
        XCTAssertEqual(failed.messages.map(\.role), [.user])
        XCTAssertEqual(failed.messages.map(\.content), ["Why is a0 zero?"])
        XCTAssertEqual(model.highlightStore.highlights.count, 1)
    }

    func testCancellationKeepsTheHighlightAndTheQuestion() async throws {
        let model = makeModel()
        let assistant = model.assistant
        assistant.script = { _, _ in throw CancellationError() }
        model.workspace.sendThreadMessage("Why is a0 zero?")
        let failed = try await waitHighlight(model.workspace)
        XCTAssertEqual(failed.askFailure, AssistantFailure.cancelled.statusLine)
        XCTAssertEqual(failed.messages.map(\.content), ["Why is a0 zero?"])
    }

    func testRetryAsksTheSameQuestionInTheSameThread() async throws {
        let model = makeModel()
        let assistant = model.assistant
        var questions: [String] = []
        assistant.script = { question, _ in
            questions.append(question)
            if questions.count == 1 { throw StubAskFailure() }
            return "Because a0 is zero. [[CAUCHY_BASIS: PDF]]"
        }
        model.workspace.sendThreadMessage("Why is a0 zero?")
        let failed = try await waitHighlight(model.workspace)
        model.workspace.retryHighlight(failed)
        let answered = try await waitHighlight(model.workspace) { $0.messages.contains { $0.role == .assistant } }
        XCTAssertEqual(questions, ["Why is a0 zero?", "Why is a0 zero?"])
        XCTAssertNil(answered.askFailure)
        XCTAssertEqual(answered.id, failed.id)
        XCTAssertTrue(answered.messages.contains { $0.role == .assistant && $0.content.contains("Because a0 is zero") })
    }

    func testReopeningAnInFlightThreadKeepsTheStreamingAnswer() async throws {
        let model = makeModel()
        let gate = AskGate()
        model.assistant.script = { question, partial in
            let saved = model.workspace.highlightStore.highlights
            XCTAssertEqual(saved.first?.messages.map(\.content), [question])
            partial("Because a0 vanishes")
            gate.markStarted()
            try await gate.waitToFinish()
            try Task.checkCancellation()
            return "Because a0 vanishes, the constant term is zero. [[CAUCHY_BASIS: PDF]]"
        }
        model.workspace.sendThreadMessage("Why is a0 zero?")
        await gate.waitUntilStarted()

        var streaming: String?
        for _ in 0..<40 {
            streaming = model.workspace.selectionThread.activeThread?.streamingAssistantText
            if streaming == "Because a0 vanishes" { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertEqual(streaming, "Because a0 vanishes")
        let id = try XCTUnwrap(model.workspace.answeringHighlightID)
        model.workspace.showHighlightList()
        model.workspace.selectHighlight(id: id)
        XCTAssertTrue(model.workspace.selectionThread.isResponding)
        XCTAssertEqual(model.workspace.selectionThread.activeThread?.anchorID, id)
        XCTAssertEqual(model.workspace.selectionThread.activeThread?.streamingAssistantText, "Because a0 vanishes")

        gate.finish()
        let answered = try await waitHighlight(model.workspace) { $0.messages.contains { $0.role == .assistant } }
        XCTAssertNil(answered.askFailure)
        XCTAssertFalse(model.workspace.selectionThread.isResponding)
    }

    func testPulseStaysInsideTheHighlightColour() {
        let trough = HighlightAnnotationService.pulseOpacity(at: 0)
        let peak = HighlightAnnotationService.pulseOpacity(at: 1.3)
        XCTAssertEqual(trough, 0.15, accuracy: 0.001)
        XCTAssertEqual(peak, 0.47, accuracy: 0.001)
        XCTAssertGreaterThan(peak, trough)
    }

    private func makeModel() -> (workspace: WorkspaceViewModel, assistant: ScriptedReadingAssistant) {
        let workspace = WorkspaceViewModel()
        workspace.workspace = DocumentWorkspace(documentURL: URL(fileURLWithPath: "/tmp/jerry-155.pdf"))
        let assistant = ScriptedReadingAssistant()
        workspace.selectionThread = SelectionThreadViewModel(assistant: assistant)
        workspace.selectionThread.activeThread = SelectionThread(
            anchorID: UUID(),
            pageIndex: 81,
            selectedText: "Suppose h(z0) = h'(z0) = 0.",
            surroundingText: "Suppose h(z0) = h'(z0) = 0. Then a0 = a1 = 0."
        )
        return (workspace, assistant)
    }

    private func waitHighlight(
        _ model: WorkspaceViewModel,
        until predicate: (Highlight) -> Bool = { $0.askFailure != nil }
    ) async throws -> Highlight {
        for _ in 0..<100 {
            if let highlight = model.highlightStore.highlights.first, predicate(highlight) {
                return highlight
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("highlight did not reach the expected state")
        throw StubAskFailure()
    }
}

private struct StubAskFailure: LocalizedError {
    var errorDescription: String? { "The model stopped." }
}

@MainActor
private final class ScriptedReadingAssistant: ReadingAssistantProtocol {
    var provider: AssistantConnectorID = .claudeCode
    var availability: ReadingAssistantAvailability = .available(.claudeCode)
    var isResponding = false
    var script: @MainActor (String, @MainActor (String) -> Void) async throws -> String

    init() {
        script = { _, _ in "" }
    }

    func resetSession(context: ReadingContext) {}
    func restoreSession(context: ReadingContext, messages: [ThreadMessage]) {}

    func ask(
        question: String,
        retrieval: AskRetrieval,
        onPartial: ((String) -> Void)?
    ) async throws -> String {
        try await script(question) { onPartial?($0) }
    }
}

private final class AskGate: @unchecked Sendable {
    private let lock = NSLock()
    private var started: CheckedContinuation<Void, Never>?
    private var didStart = false
    private var finish: CheckedContinuation<Void, Error>?

    func markStarted() {
        lock.lock()
        didStart = true
        let waiting = started
        started = nil
        lock.unlock()
        waiting?.resume()
    }

    func waitUntilStarted() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.lock()
            if didStart {
                lock.unlock()
                cont.resume()
            } else {
                started = cont
                lock.unlock()
            }
        }
    }

    func waitToFinish() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            lock.lock()
            finish = cont
            lock.unlock()
        }
    }

    func finish() {
        lock.lock()
        let waiting = finish
        finish = nil
        lock.unlock()
        waiting?.resume()
    }
}
