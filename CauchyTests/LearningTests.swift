import XCTest
import PDFKit
import AppKit
@testable import Cauchy

#if DEBUG
@MainActor
final class LearningUIFixtureTests: XCTestCase {
    private func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("cauchy-ui-fixture-\(UUID().uuidString)")
    }

    func testFixtureRootRejectsNormalDirectoriesUnmarkedStorageAndEscapingLinks() throws {
        XCTAssertNil(LearningUIFixture.requestedRoot(arguments: ["Cauchy"], bundleRoot: nil))
        XCTAssertEqual(LearningUIFixture.requestedRoot(arguments: ["Cauchy", "--learning-ui-fixture"], bundleRoot: nil), "")
        XCTAssertEqual(LearningUIFixture.requestedRoot(arguments: ["Cauchy", "--learning-ui-fixture", "/tmp/cauchy-ui-fixture-example"], bundleRoot: "/tmp/other"), "/tmp/cauchy-ui-fixture-example")
        XCTAssertThrowsError(try LearningUIFixture.validatedRoot(NSHomeDirectory()))
        XCTAssertThrowsError(try LearningUIFixture.validatedRoot("/tmp"))
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sentinel = root.appendingPathComponent("sentinel.txt")
        try "Preserve unrelated data".write(to: sentinel, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try LearningUIFixture.validatedRoot(root.path))
        XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "Preserve unrelated data")
        try LearningUIFixture.marker.write(to: root.appendingPathComponent("fixture-format.txt"), atomically: true, encoding: .utf8)
        XCTAssertNoThrow(try LearningUIFixture.validatedRoot(root.path))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("workspaces"), withDestinationURL: URL(fileURLWithPath: NSHomeDirectory()))
        XCTAssertThrowsError(try LearningUIFixture.validatedRoot(root.path))
    }

    func testFixtureSeedsCompleteAndBlockedChaptersAndRefusesNormalLibraryImports() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = LearningUIFixtureController(rootPath: root.path)
        await controller.load()
        XCTAssertNil(controller.error)
        let library = try XCTUnwrap(controller.library)
        let document = try XCTUnwrap(library.selectedDocument)
        XCTAssertTrue(library.isVerificationFixture)
        XCTAssertTrue(document.isVerificationFixture)
        XCTAssertEqual(document.pdfDocument.pageCount, 2)
        XCTAssertTrue(document.snapshot.documentURL.path.hasPrefix(root.path))
        XCTAssertEqual(document.learning.sessions.count, 2)
        XCTAssertEqual(document.learning.sessions[0].answerDraft, "Saved fixture draft: closedness keeps the limit in K.")
        XCTAssertEqual(document.learning.sessions[0].hintsRevealed, 1)
        let map = try XCTUnwrap(document.studyMap.map)
        let course = try XCTUnwrap(map.course)
        let due = try XCTUnwrap(map.nextDelayedReview(sessions: document.learning.sessions, now: Date()))
        XCTAssertEqual(due.target.kind, .application)
        XCTAssertEqual(due.unit.id, LearningUIFixture.imageID)
        XCTAssertTrue(due.dueAt < Date())
        XCTAssertNotNil(map.chapterRequest(for: course.modules[0]))
        XCTAssertNil(map.chapterRequest(for: course.modules[1]))
        XCTAssertTrue(map.chapterAvailability(for: course.modules[1]).blockers.contains { $0.kind == .proof })
        XCTAssertTrue(map.chapterAvailability(for: course.modules[1]).blockers.contains { $0.kind == .extraction && $0.pageIndex == 1 })
        library.openNotes()
        XCTAssertNotNil(library.errorMessage)
        await library.open(URL(fileURLWithPath: "/tmp/non-fixture-document.pdf"))
        XCTAssertEqual(library.documents.count, 1)
        XCTAssertEqual(library.summaries.count, 1)
        var unrelated = DocumentWorkspace(documentURL: URL(fileURLWithPath: "/tmp/unrelated-reader.pdf"))
        let before = unrelated
        library.synchronize(&unrelated, bookmarkData: nil)
        XCTAssertEqual(unrelated.learningSessions, before.learningSessions)
        XCTAssertNil(unrelated.learningStudyMap)
        try await controller.flush()
    }

    func testOfflineChapterRescueAndDraftSurviveARealTemporaryPersistenceRestart() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = LearningUIFixtureController(rootPath: root.path)
        await controller.load()
        let library = try XCTUnwrap(controller.library)
        let document = try XCTUnwrap(library.selectedDocument)
        let map = try XCTUnwrap(document.studyMap.map)
        let module = try XCTUnwrap(map.course?.modules.first)
        let request = try XCTUnwrap(map.chapterRequest(for: module))
        let initialChecked = request.units.reduce(0) { $0 + $1.checkedTargetCount(sessions: document.learning.sessions) }
        let source = try LearningSourceBuilder.pages(1...1, in: document.pdfDocument)
        document.learning.startChapter(request: request, source: source)
        await document.learning.waitForOperation()
        XCTAssertNil(document.learning.errorMessage)
        let id = try XCTUnwrap(document.learning.session?.id)
        let question = try XCTUnwrap(document.learning.session?.question)
        document.learning.answerDraft = "Saved original fixture argument."
        document.learning.setChapterPosition("reasoning")
        document.learning.setChapterScrollOffset(181.25)
        document.learning.openPrerequisiteRescue()
        document.learning.rescueDraft = "fixture correct"
        document.learning.submitAnswer()
        await document.learning.waitForOperation()
        XCTAssertEqual(document.learning.session?.chapter?.rescueFeedback?.grade, .correct)
        try await controller.flush()

        let restarted = LearningUIFixtureController(rootPath: root.path)
        await restarted.load()
        XCTAssertNil(restarted.error)
        let restored = try XCTUnwrap(restarted.library?.selectedDocument)
        restored.learning.select(id)
        XCTAssertEqual(restored.learning.session?.question, question)
        XCTAssertEqual(restored.learning.answerDraft, "Saved original fixture argument.")
        XCTAssertEqual(restored.learning.rescueDraft, "fixture correct")
        XCTAssertTrue(restored.learning.session?.chapter?.rescueVisible == true)
        XCTAssertTrue(restored.learning.session?.assistanceUsed == true)
        restored.learning.returnToChapter()
        XCTAssertEqual(restored.learning.session?.chapter?.scrollOffset, 181.25)
        XCTAssertEqual(restored.learning.session?.chapter?.position, "reasoning")
        XCTAssertEqual(restored.learning.session?.id, id)
        restored.learning.answerDraft = "fixture correct"
        restored.learning.submitAnswer(); await restored.learning.waitForOperation(); restored.learning.advance()
        XCTAssertFalse(restored.learning.session?.passedExitCheck == true)
        restored.learning.freshChapterCheck(); await restored.learning.waitForOperation()
        XCTAssertNil(restored.learning.errorMessage)
        XCTAssertNotEqual(restored.learning.session?.question, question)
        restored.learning.answerDraft = "fixture correct"
        restored.learning.submitAnswer(); await restored.learning.waitForOperation()
        XCTAssertTrue(restored.learning.session?.passedExitCheck == true)
        XCTAssertEqual(request.units.reduce(0) { $0 + $1.checkedTargetCount(sessions: restored.learning.sessions) }, initialChecked)
        try await restarted.flush()
    }

    func testInvalidFixtureLaunchFailsWithoutOpeningAStore() async {
        let controller = LearningUIFixtureController(rootPath: "/tmp")
        await controller.load()
        XCTAssertNil(controller.library)
        XCTAssertNotNil(controller.error)
    }
}
#endif

private struct RecordedProofRun: Decodable {
    struct Case: Decodable {
        struct Input: Decodable {
            let source: String
            let question: String
            let expectedAnswer: String
            let gradingCriteria: [String]
            let studentAnswer: String
            var learningQuestion: LearningQuestion {
                .init(prompt: question, expectedAnswer: expectedAnswer, hints: [], kind: .proof, gradingCriteria: gradingCriteria)
            }
        }
        let name: String
        let input: Input
        let assessment: LearningAssessment
    }
    let model: String
    let complete: Bool
    let results: [Case]
}

@MainActor
private final class RecordedProofTutor: LearningTutorProtocol {
    let providerID = "codex-recorded-replay"
    let modelID: String?
    let lesson: LearningLesson
    let records: [RecordedProofRun.Case]
    init(lesson: LearningLesson, records: [RecordedProofRun.Case], model: String) {
        self.lesson = lesson; self.records = records; modelID = model
    }
    func makeLesson(source: LearningSource) async throws -> LearningLesson { lesson }
    func assess(question: LearningQuestion, answer: String, source: LearningSource) async throws -> LearningAssessment {
        guard let record = records.first(where: { $0.input.question == question.prompt && $0.input.studentAnswer == answer
            && $0.input.gradingCriteria == question.gradingCriteria && $0.input.expectedAnswer == question.expectedAnswer }),
              source.passages.count == 1, source.passages[0].text == record.input.source else { throw LearningError.invalidResponse }
        return record.assessment
    }
    func newExitQuestion(lesson: LearningLesson, source: LearningSource, previous: [String]) async throws -> LearningQuestion {
        throw LearningError.invalidResponse
    }
}

@MainActor
final class LearningRecordedProofTests: XCTestCase {
    func testCapturedModelAssessmentsReplayAnEntireAuthoredTutoringJourney() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let run = try JSONDecoder().decode(RecordedProofRun.self, from: Data(contentsOf: root
            .appendingPathComponent("docs/evaluation/proof-assessment-expanded-results.json")))
        XCTAssertTrue(run.complete)
        let names = ["finite_examples_as_universal_proof", "valid_linear_combination_proof", "valid_fibre_equivalence_proof"]
        let records = try names.map { name in try XCTUnwrap(run.results.first { $0.name == name }) }
        XCTAssertEqual(Set(records.map { $0.input.source }).count, 1)
        let source = LearningSource(passages: [.init(pageIndex: 0, text: records[0].input.source)])
        let quote = "Theorem 1. The kernel of a linear map is a subspace of its domain."
        var practice = records[1].input.learningQuestion
        practice = .init(prompt: practice.prompt, expectedAnswer: practice.expectedAnswer,
            hints: ["Work from the three source subspace conditions."], kind: .proof, gradingCriteria: practice.gradingCriteria)
        let lesson = LearningLesson(title: "Authored proof evaluation replay", objective: "Justify all subspace conditions for a kernel.",
            sourceQuote: quote, explanation: "Derive zero membership independently, then verify both universal closure conditions.",
            workedExample: "For T(x,y)=x, the kernel is the vertical coordinate subspace; the general argument must handle arbitrary maps and vectors.",
            diagnostic: records[0].input.learningQuestion, practice: practice, exitCheck: records[2].input.learningQuestion,
            proof: .init(statement: quote, assumptions: ["T is linear between real vector spaces."],
                strategy: "Use the subspace definition and the two linearity identities.",
                steps: [.init(claim: "T(0)=T(0v)=0T(v)=0.", justification: "Scalar preservation establishes zero membership independently."),
                        .init(claim: "For arbitrary u,v in ker(T), T(u+v)=T(u)+T(v)=0.", justification: "Additivity and the definition of the kernel establish addition closure."),
                        .init(claim: "For arbitrary real a and v in ker(T), T(av)=aT(v)=0.", justification: "Scalar preservation establishes scalar closure.")],
                conclusion: "The kernel contains zero and satisfies both universal closure conditions, hence is a subspace.",
                sourceQuote: "Scalar preservation gives T(0_V)=T(0v)=0T(v)=0_W"))
        let tutor = RecordedProofTutor(lesson: lesson, records: records, model: run.model)
        let vm = LearningViewModel(makeTutor: { tutor })
        let target = LearningStudyTarget(unitID: UUID(), kind: .proof, objective: lesson.objective)
        vm.start(source: source, target: target); await vm.waitForOperation()
        XCTAssertNil(vm.errorMessage)
        let id = try XCTUnwrap(vm.session?.id)
        vm.answerDraft = records[0].input.studentAnswer
        vm.submitAnswer(); await vm.waitForOperation()
        XCTAssertNotEqual(vm.session?.feedback?.grade, .correct)
        vm.advance(); XCTAssertEqual(vm.session?.phase, .lesson)
        vm.advance(); XCTAssertEqual(vm.session?.phase, .practice)
        vm.answerDraft = records[1].input.studentAnswer
        vm.submitAnswer(); await vm.waitForOperation()
        XCTAssertEqual(vm.session?.feedback?.grade, .correct)
        vm.advance(); XCTAssertEqual(vm.session?.phase, .exitCheck)
        // Restart after teaching and practice, before the independent answer.
        let restarted = LearningViewModel(makeTutor: { tutor })
        restarted.restore(try JSONDecoder().decode([LearningSession].self, from: JSONEncoder().encode(vm.sessions)))
        restarted.select(id)
        restarted.answerDraft = records[2].input.studentAnswer
        restarted.submitAnswer(); await restarted.waitForOperation(); restarted.advance()
        XCTAssertNil(restarted.errorMessage)
        XCTAssertTrue(restarted.session?.passedExitCheck == true)
        XCTAssertEqual(restarted.session?.attempts.map(\.question.prompt), records.map { $0.input.question })
        XCTAssertEqual(restarted.session?.attempts.map(\.assessment.criteria), records.map { $0.assessment.criteria })
        XCTAssertEqual(restarted.session?.attempts.map(\.modelID), Array(repeating: run.model, count: 3))
        XCTAssertEqual(restarted.session?.studyTarget?.id, target.id)
    }
}

@MainActor
final class LearningWorkspaceTests: XCTestCase {
    func testLearningProgressSurvivesAnOlderReaderRewritingTheSharedWorkspace() async throws {
        let (root, persistence, library, reader, document) = try fixture()
        defer {
            withExtendedLifetime((library, reader)) {}
            try? FileManager.default.removeItem(at: root)
        }
        document.learning.answerDraft = "Saved before the old reader writes"
        try await persistence.flushAll()
        let stored = await persistence.loadWorkspace(id: document.id)
        var saved = try XCTUnwrap(stored).workspace
        let date = Date(timeIntervalSince1970: 1_711_111_111)
        saved.learningStudyMap = .init(pageSignatures: ["fixture"], pages: [.init(pageIndex: 0, status: .mapped)], updatedAt: date)
        try await persistence.saveWorkspace(saved, bookmarkData: nil)
        let map = saved.learningStudyMap
        let highlight = Highlight(pageIndex: 0, selectedText: "A newer reader annotation", note: "Keep this too", createdAt: date, updatedAt: date)
        var oldReader = saved
        oldReader.learningSessions = []
        oldReader.learningStudyMap = nil
        oldReader.highlights = [highlight]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Bypass the new writer: this is exactly what an older binary does.
        try encoder.encode(PersistedWorkspace(workspace: oldReader, bookmarkData: nil))
            .write(to: persistence.workspaceFileURL(for: document.id), options: .atomic)
        let fresh = DocumentPersistenceService(root: persistence.applicationSupportRoot())
        let restored = await fresh.loadWorkspace(id: document.id)
        XCTAssertEqual(restored?.workspace.learningSessions.first?.answerDraft, "Saved before the old reader writes")
        XCTAssertEqual(restored?.workspace.learningStudyMap, map)
        XCTAssertEqual(restored?.workspace.highlights, [highlight])

        // A later learning-only edit must not roll the reader fields back.
        document.learning.answerDraft = "Continue after the reader edit"
        try await persistence.flushAll()
        let after = await fresh.loadWorkspace(id: document.id)
        XCTAssertEqual(after?.workspace.learningSessions.first?.answerDraft, "Continue after the reader edit")
        XCTAssertEqual(after?.workspace.highlights, [highlight])
        XCTAssertEqual(after?.workspace.learningStudyMap, map)
    }

    func testStaleReaderCannotRollBackLearningWrittenWithinTheSameSecond() async throws {
        let (root, persistence, library, reader, document) = try fixture()
        defer {
            withExtendedLifetime((library, reader)) {}
            try? FileManager.default.removeItem(at: root)
        }
        document.learning.answerDraft = "Save the initial workspace"
        try await persistence.flushAll()
        let loaded = await persistence.loadWorkspace(id: document.id)
        var old = try XCTUnwrap(loaded).workspace
        old.learningStudyMap = .init(pageSignatures: ["fixture"], pages: [.init(pageIndex: 0)],
            updatedAt: Date(timeIntervalSince1970: 1_711_111_111.25))
        try await persistence.saveWorkspace(old, bookmarkData: nil)
        var current = old
        current.learningStudyMap?.pages[0].status = .mapped
        current.learningStudyMap?.updatedAt = Date(timeIntervalSince1970: 1_711_111_111.75)
        try await persistence.saveWorkspace(current, bookmarkData: nil, learningOnly: true)
        let fresh = DocumentPersistenceService(root: persistence.applicationSupportRoot())
        let restored = await fresh.loadWorkspace(id: document.id)
        XCTAssertEqual(restored?.workspace.learningStudyMap, current.learningStudyMap)
        try await persistence.saveWorkspace(old, bookmarkData: nil)
        let after = await fresh.loadWorkspace(id: document.id)
        XCTAssertEqual(after?.workspace.learningStudyMap, current.learningStudyMap)
    }

    func testDocumentEntryOpensWholeNotesAndPassageStudyIsExplicitWithoutLosingDraft() async throws {
        let (root, persistence, library, reader, document) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        document.learning.answerDraft = "Keep this reasoning while I review the whole subject."
        let lessonID = try XCTUnwrap(document.learning.selectedSessionID)
        document.learning.errorMessage = LearningError.noText.localizedDescription
        await library.navigate(to: .document(document.id))
        XCTAssertEqual(library.destination, .document(document.id))
        XCTAssertNil(document.learning.selectedSessionID)
        XCTAssertNil(document.learning.errorMessage)
        XCTAssertFalse(document.requestsNewSection)
        await library.navigate(to: .passage(document.id))
        XCTAssertEqual(library.destination, .passage(document.id))
        XCTAssertTrue(document.requestsNewSection)
        await library.navigate(to: .session(document: document.id, session: lessonID))
        XCTAssertEqual(document.learning.answerDraft, "Keep this reasoning while I review the whole subject.")
        document.learning.showSections()
        library.activate(from: reader)
        XCTAssertEqual(library.destination, .document(document.id))
        library.activate(from: reader, newSection: true)
        XCTAssertEqual(library.destination, .passage(document.id))
        try await persistence.flushAll()
    }
    func testReaderRestorePrefersItsDocumentOverMoreRecentLearningSource() {
        let reading = WorkspaceSummary(workspaceID: UUID(), documentURL: URL(fileURLWithPath: "/tmp/reading.pdf"),
            lastOpenedAt: Date(timeIntervalSince1970: 100), highlightCount: 0)
        let learning = WorkspaceSummary(workspaceID: UUID(), documentURL: URL(fileURLWithPath: "/tmp/learning.pdf"),
            lastOpenedAt: Date(timeIntervalSince1970: 200), highlightCount: 0)
        XCTAssertEqual(WorkspaceViewModel.restoreSummary(in: [learning, reading], preferredWorkspaceID: reading.workspaceID)?.workspaceID, reading.workspaceID)
        XCTAssertEqual(WorkspaceViewModel.restoreSummary(in: [learning, reading], preferredWorkspaceID: nil)?.workspaceID, learning.workspaceID)
        XCTAssertNil(WorkspaceViewModel.restoreSummary(in: [learning, reading], preferredWorkspaceID: UUID()))
    }

    private func fixture() throws -> (URL, DocumentPersistenceService, LearningLibraryStore, WorkspaceViewModel, LearningDocument) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("notes.pdf")
        let data = NSMutableData()
        var bounds = CGRect(x: 0, y: 0, width: 600, height: 800)
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &bounds, nil))
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSAttributedString(string: learningSource.passages[0].text, attributes: [.font: NSFont.systemFont(ofSize: 12)])
            .draw(in: CGRect(x: 30, y: 500, width: 520, height: 220))
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
        try (data as Data).write(to: url)
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        let source = try LearningSourceBuilder.pages(1...1, in: pdf)
        var session = LearningSession(source: source, lesson: learningLesson(), providerID: "test", modelID: "test-model")
        session.phase = .practice
        let workspace = DocumentWorkspace(documentURL: url, learningSessions: [session])
        let persistence = DocumentPersistenceService(root: root.appendingPathComponent("workspaces"))
        let library = LearningLibraryStore(persistence: persistence)
        let reader = WorkspaceViewModel(persistence: persistence, learningLibrary: library)
        reader.workspace = workspace
        reader.pdfDocument = pdf
        reader.highlightStore.load(from: workspace)
        library.activate(from: reader)
        let document = try XCTUnwrap(library.selectedDocument)
        document.learning.select(session.id)
        return (root, persistence, library, reader, document)
    }

    func testLearningDraftAndSourceSurviveClosingTheReader() async throws {
        let (root, persistence, _, reader, document) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        document.learning.answerDraft = "Work before closing the reader"
        reader.closeDocument()
        XCTAssertNil(reader.pdfDocument)
        XCTAssertEqual(document.learning.session?.phase, .practice)
        XCTAssertEqual(document.learning.answerDraft, "Work before closing the reader")
        XCTAssertEqual(document.pdfDocument.pageCount, 1)

        document.learning.answerDraft = "Continue working in the learning window"
        try await persistence.flushAll()
        let saved = await persistence.loadWorkspace(id: document.id)
        XCTAssertEqual(saved?.workspace.learningSessions.first?.answerDraft, "Continue working in the learning window")
    }

    func testReaderAndLearningWritesPreserveEachOthersChanges() async throws {
        let (root, persistence, library, reader, document) = try fixture()
        defer {
            OpenDocumentRegistry.shared.release(by: reader)
            try? FileManager.default.removeItem(at: root)
        }
        OpenDocumentRegistry.shared.claim(document.snapshot.documentURL, by: reader)
        document.learning.answerDraft = "Latest learning draft"
        let date = Date(timeIntervalSince1970: 1_711_111_111)
        let conversationID = UUID()
        let conversation = [ThreadMessage(role: .user, content: "A whole-document reader question", createdAt: date)]
        reader.selectionThread.loadDocumentConversation(id: conversationID, messages: conversation)
        let highlight = Highlight(pageIndex: 0, selectedText: "A reader annotation", note: "Keep this note", createdAt: date, updatedAt: date)
        reader.highlightStore.highlights = [highlight]
        reader.contextPanelWidth = 480
        reader.persistWorkspace()
        try await persistence.flushAll()
        var saved = await persistence.loadWorkspace(id: document.id)
        XCTAssertEqual(saved?.workspace.highlights, [highlight])
        XCTAssertEqual(saved?.workspace.contextPanelWidth, 480)
        XCTAssertEqual(saved?.workspace.learningSessions.first?.answerDraft, "Latest learning draft")
        XCTAssertEqual(saved?.workspace.documentConversationID, conversationID)
        XCTAssertEqual(saved?.workspace.documentConversation, conversation)
        XCTAssertEqual(document.snapshot.documentConversation, conversation)

        reader.closeDocument()
        document.learning.answerDraft = "A later learning edit"
        try await persistence.flushAll()
        saved = await persistence.loadWorkspace(id: document.id)
        XCTAssertEqual(saved?.workspace.highlights, [highlight])
        XCTAssertEqual(saved?.workspace.contextPanelWidth, 480)
        XCTAssertEqual(saved?.workspace.learningSessions.first?.answerDraft, "A later learning edit")
        XCTAssertEqual(saved?.workspace.documentConversationID, conversationID)
        XCTAssertEqual(saved?.workspace.documentConversation, conversation)
        let restarted = DocumentPersistenceService(root: persistence.applicationSupportRoot())
        let reloaded = await restarted.loadWorkspace(id: document.id)
        XCTAssertEqual(reloaded?.workspace.documentConversationID, conversationID)
        XCTAssertEqual(reloaded?.workspace.documentConversation, conversation)
        XCTAssertEqual(reloaded?.workspace.learningSessions.first?.answerDraft, "A later learning edit")
        XCTAssertTrue(library.selectedDocument === document)
    }

    func testOpeningLearningAgainReusesItsCurrentLessonAndDraft() async throws {
        let (root, persistence, library, reader, document) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        document.learning.answerDraft = "Keep this unsent reasoning"
        let selectedSession = document.learning.selectedSessionID
        library.activate(from: reader)
        XCTAssertTrue(library.selectedDocument === document)
        XCTAssertEqual(document.learning.selectedSessionID, selectedSession)
        XCTAssertEqual(document.learning.answerDraft, "Keep this unsent reasoning")
        XCTAssertFalse(document.pdfDocument === reader.pdfDocument)

        // Explicitly starting a section leaves the existing draft in its
        // saved lesson; choosing that lesson cancels the new-section intent.
        library.activate(from: reader, newSection: true)
        XCTAssertNil(document.learning.selectedSessionID)
        XCTAssertTrue(document.requestsNewSection)
        await library.navigate(to: .session(document: document.id, session: try XCTUnwrap(selectedSession)))
        XCTAssertFalse(document.requestsNewSection)
        XCTAssertEqual(document.learning.answerDraft, "Keep this unsent reasoning")
        try await persistence.flushAll()
    }

    func testSwitchingReadersDocumentDoesNotReplaceTheLearningSource() async throws {
        let (root, persistence, library, reader, document) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        document.learning.answerDraft = "Reasoning about the original notes"
        let originalURL = document.snapshot.documentURL
        reader.closeDocument()
        reader.workspace = DocumentWorkspace(documentURL: root.appendingPathComponent("other-notes.pdf"))
        reader.pdfDocument = PDFDocument()
        reader.persistWorkspace()
        XCTAssertTrue(library.selectedDocument === document)
        XCTAssertEqual(document.snapshot.documentURL, originalURL)
        XCTAssertEqual(document.learning.answerDraft, "Reasoning about the original notes")
        XCTAssertTrue(LearningSourceBuilder.matches(document.learning.session!.source, document: document.pdfDocument))
        try await persistence.flushAll()
    }
}

private let learningSource = LearningSource(passages: [
    .init(pageIndex: 0, text: "A linear map preserves addition and scalar multiplication. Its kernel is the set of vectors mapped to zero.")
])

private func learningQuestion(_ prompt: String, hints: [String] = []) -> LearningQuestion {
    .init(prompt: prompt, expectedAnswer: "Explain that a linear map sends the zero vector to zero.", hints: hints)
}

private func learningLesson() -> LearningLesson {
    .init(title: "Linear maps", objective: "Explain why a linear map sends zero to zero.",
          sourceQuote: "A linear map preserves addition and scalar multiplication.",
          explanation: "Apply linearity to a zero scalar.", workedExample: "For a matrix map, multiply the zero vector.",
          diagnostic: learningQuestion("What does a linear map do to zero? Explain."),
          practice: learningQuestion("Explain why a matrix sends zero to zero.", hints: ["Use scalar multiplication."]),
          exitCheck: learningQuestion("Can a map sending zero to a nonzero vector be linear? Explain."))
}

private func assessment(_ grade: LearningGrade) -> LearningAssessment {
    .init(grade: grade, feedback: "Consider scalar multiplication.", nextStep: "Explain the step using a zero scalar.")
}

@MainActor
private final class TestLearningTutor: LearningTutorProtocol {
    var providerID = "test-provider"
    var modelID: String? = "test-model"
    var grade: LearningGrade = .incorrect
    var shouldFail = false
    var assessmentCount = 0
    var freshQuestionCount = 0
    var excludedQuestions: [String] = []

    func makeLesson(source: LearningSource) async throws -> LearningLesson {
        if shouldFail { throw LearningError.invalidResponse }
        return learningLesson()
    }

    func assess(question: LearningQuestion, answer: String, source: LearningSource) async throws -> LearningAssessment {
        assessmentCount += 1
        if shouldFail { throw LearningError.invalidResponse }
        return assessment(grade)
    }

    func newExitQuestion(lesson: LearningLesson, source: LearningSource, previous: [String]) async throws -> LearningQuestion {
        freshQuestionCount += 1
        excludedQuestions = previous
        if shouldFail { throw LearningError.invalidResponse }
        return learningQuestion("Is translation by a nonzero vector linear? Explain.")
    }
}

@MainActor
final class LearningFlowTests: XCTestCase {
    func testPacedProofPreservesAllStepsAndResumesWithoutCreatingEvidence() throws {
        var lesson = learningLesson()
        let steps = (0..<12).map { LearningProofStep(claim: "Claim \($0)", justification: "Reason \($0)") }
        lesson.proof = .init(statement: "Statement", assumptions: ["Given"], strategy: "Strategy",
            steps: steps, conclusion: "Conclusion", sourceQuote: lesson.sourceQuote)
        var saved = LearningSession(source: learningSource, lesson: lesson, providerID: "fixture", modelID: nil)
        saved.phase = .lesson
        let vm = LearningViewModel()
        vm.restore([saved]); vm.select(saved.id)
        XCTAssertEqual(vm.session?.currentLessonPart, .proofOverview)
        vm.continueLesson()
        XCTAssertEqual(vm.session?.currentLessonPart, .proofStep(0))
        vm.selectLessonPart(8)
        XCTAssertEqual(vm.session?.currentLessonPart, .proofStep(7))
        let decoded = try JSONDecoder().decode(LearningSession.self, from: JSONEncoder().encode(vm.session!))
        vm.restore([decoded]); vm.select(decoded.id)
        XCTAssertEqual(vm.session?.currentLessonPart, .proofStep(7))
        XCTAssertEqual(vm.session?.lesson.proof?.steps, steps)
        XCTAssertTrue(vm.session!.attempts.isEmpty)
        XCTAssertFalse(vm.session!.passedExitCheck)
        vm.selectLessonPart(-1); vm.selectLessonPart(1_000)
        XCTAssertEqual(vm.session?.currentLessonPart, .proofStep(7))
        vm.selectLessonPart(13)
        XCTAssertEqual(vm.session?.currentLessonPart, .proofConclusion)
        vm.continueLesson()
        XCTAssertEqual(vm.session?.currentLessonPart, .example)
        vm.continueLesson()
        XCTAssertEqual(vm.session?.phase, .practice)
        vm.selectLessonPart(0)
        XCTAssertEqual(vm.session?.phase, .practice)
        vm.reviewIdea()
        XCTAssertEqual(vm.session?.currentLessonPart, .proofOverview)
    }

    func testLegacyAndInvalidLessonPositionsSafelyOpenAnAvailablePart() throws {
        var session = LearningSession(source: learningSource, lesson: learningLesson(), providerID: "fixture", modelID: nil)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any])
        json.removeValue(forKey: "lessonPartIndex")
        let legacy = try JSONDecoder().decode(LearningSession.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(legacy.currentLessonPart, .idea)
        session.lessonPartIndex = 1_000
        XCTAssertEqual(session.currentLessonPart, .example)
        session.lessonPartIndex = -1
        XCTAssertEqual(session.currentLessonPart, .idea)
    }

    private func start(_ tutor: TestLearningTutor) async -> LearningViewModel {
        let vm = LearningViewModel { tutor }
        vm.start(source: learningSource)
        await vm.waitForOperation()
        return vm
    }

    private func answer(_ vm: LearningViewModel, tutor: TestLearningTutor, grade: LearningGrade) async {
        tutor.grade = grade
        vm.answerDraft = "By linearity, multiplying by zero gives zero."
        vm.submitAnswer()
        await vm.waitForOperation()
    }

    func testCorrectDiagnosticSkipsTeachingWithoutClaimingCompletion() async {
        let tutor = TestLearningTutor()
        let vm = await start(tutor)
        await answer(vm, tutor: tutor, grade: .correct)
        vm.advance()
        XCTAssertEqual(vm.session?.phase, .exitCheck)
        XCTAssertFalse(vm.session!.passedExitCheck)
        XCTAssertEqual(vm.session?.attempts.count, 1)
    }

    func testIncorrectDiagnosticRoutesThroughTeachingAndGuidedPractice() async {
        let tutor = TestLearningTutor()
        let vm = await start(tutor)
        await answer(vm, tutor: tutor, grade: .incorrect)
        vm.advance()
        XCTAssertEqual(vm.session?.phase, .lesson)
        vm.advance()
        XCTAssertEqual(vm.session?.phase, .practice)
        XCTAssertEqual(vm.answerDraft, "")
    }

    func testPracticeHelpIsRecordedAndNeverAvailableInExitCheck() async {
        let tutor = TestLearningTutor()
        let vm = await start(tutor)
        await answer(vm, tutor: tutor, grade: .incorrect)
        vm.advance()
        vm.advance()
        vm.revealHint()
        await answer(vm, tutor: tutor, grade: .correct)
        XCTAssertTrue(vm.session!.attempts.last!.assistanceUsed)
        vm.advance()
        vm.revealHint()
        vm.revealSolution()
        XCTAssertEqual(vm.session?.hintsRevealed, 0)
        XCTAssertFalse(vm.session!.solutionRevealed)
        await answer(vm, tutor: tutor, grade: .correct)
        vm.advance()
        XCTAssertEqual(vm.session?.phase, .complete)
        XCTAssertTrue(vm.session!.passedExitCheck)
        XCTAssertEqual(vm.session?.attempts.last?.providerID, "test-provider")
        XCTAssertEqual(vm.session?.attempts.last?.modelID, "test-model")
    }

    func testUncertainOrAssistedExitDoesNotCountAsPassed() async {
        let tutor = TestLearningTutor()
        let vm = await start(tutor)
        await answer(vm, tutor: tutor, grade: .correct)
        vm.advance()
        await answer(vm, tutor: tutor, grade: .uncertain)
        vm.advance()
        XCTAssertFalse(vm.session!.passedExitCheck)

        var session = vm.session!
        session.attempts.append(.init(phase: .exitCheck, question: session.lesson.exitCheck,
                                     answer: "An answer", assessment: assessment(.correct), assistanceUsed: true,
                                     providerID: "test", modelID: nil))
        XCTAssertFalse(session.passedExitCheck)
    }

    func testRetryAfterExitRequiresAFreshProblemAndKeepsEarlierEvidence() async {
        let tutor = TestLearningTutor()
        let vm = await start(tutor)
        await answer(vm, tutor: tutor, grade: .correct)
        vm.advance()
        let firstExit = vm.session!.lesson.exitCheck.prompt
        await answer(vm, tutor: tutor, grade: .incorrect)
        vm.advance()
        vm.practiseAgain()
        vm.advance()
        await answer(vm, tutor: tutor, grade: .correct)
        vm.advance()
        await vm.waitForOperation()
        XCTAssertEqual(vm.session?.phase, .exitCheck)
        XCTAssertNotEqual(vm.session?.question?.prompt, firstExit)
        XCTAssertTrue(tutor.excludedQuestions.contains(firstExit))
        XCTAssertEqual(vm.session?.attempts.filter { $0.phase == .exitCheck }.count, 1)
    }

    func testFailedAssessmentKeepsDraftAndAddsNoEvidence() async {
        let tutor = TestLearningTutor()
        let vm = await start(tutor)
        tutor.shouldFail = true
        await answer(vm, tutor: tutor, grade: .correct)
        XCTAssertFalse(vm.answerDraft.isEmpty)
        XCTAssertTrue(vm.session!.attempts.isEmpty)
        XCTAssertNil(vm.session?.feedback)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isBusy)
    }

    func testPracticeMustBeCorrectBeforeAnExitCheck() async {
        for grade in [LearningGrade.incorrect, .partial, .uncertain] {
            let tutor = TestLearningTutor()
            let vm = await start(tutor)
            vm.studyInstead()
            vm.advance()
            await answer(vm, tutor: tutor, grade: grade)
            vm.advance()
            XCTAssertEqual(vm.session?.phase, .practice)
            XCTAssertEqual(tutor.freshQuestionCount, 0)
            vm.tryAgain()
            XCTAssertNil(vm.session?.feedback)
            await answer(vm, tutor: tutor, grade: .correct)
            vm.advance()
            XCTAssertEqual(vm.session?.phase, .exitCheck)
        }
    }

    func testStudyingFirstCreatesNoAssessmentEvidence() async {
        let tutor = TestLearningTutor()
        let vm = await start(tutor)
        vm.studyInstead()
        XCTAssertEqual(vm.session?.phase, .lesson)
        XCTAssertTrue(vm.session!.attempts.isEmpty)
        XCTAssertEqual(tutor.assessmentCount, 0)
        XCTAssertFalse(vm.session!.passedExitCheck)
    }

    func testOutsideHelpPreventsIndependentPassAndSurvivesPersistence() async throws {
        let tutor = TestLearningTutor()
        let vm = await start(tutor)
        // Self-reported outside help is only editable during an exit attempt.
        vm.outsideHelpUsed = true
        XCTAssertFalse(vm.outsideHelpUsed)
        await answer(vm, tutor: tutor, grade: .correct)
        vm.advance()
        vm.outsideHelpUsed = true
        let restored = try JSONDecoder().decode(LearningSession.self, from: JSONEncoder().encode(vm.session!))
        XCTAssertTrue(restored.outsideHelpUsed == true)
        await answer(vm, tutor: tutor, grade: .correct)
        vm.outsideHelpUsed = false
        XCTAssertTrue(vm.outsideHelpUsed)
        vm.advance()
        XCTAssertFalse(vm.session!.passedExitCheck)
        XCTAssertEqual(vm.session?.progressLabel, "Correct with help")
        XCTAssertTrue(vm.session!.latestExitAttempt!.assistanceUsed)
    }

    func testUncertainResultDoesNotAttributeFailureToStudent() async {
        let tutor = TestLearningTutor()
        let vm = await start(tutor)
        await answer(vm, tutor: tutor, grade: .correct)
        vm.advance()
        await answer(vm, tutor: tutor, grade: .uncertain)
        vm.advance()
        XCTAssertEqual(vm.session?.progressLabel, "Assessment inconclusive")
        XCTAssertFalse(vm.session!.passedExitCheck)
    }

    func testPracticeRevisionKeepsHelpAndEarlierAttempts() async {
        let tutor = TestLearningTutor()
        let vm = await start(tutor)
        vm.studyInstead()
        vm.advance()
        vm.revealSolution()
        XCTAssertFalse(vm.session!.solutionRevealed)
        vm.revealHint()
        await answer(vm, tutor: tutor, grade: .partial)
        vm.revealSolution()
        vm.tryAgain()
        XCTAssertTrue(vm.session!.solutionRevealed)
        await answer(vm, tutor: tutor, grade: .correct)
        XCTAssertEqual(vm.session?.attempts.count, 2)
        XCTAssertTrue(vm.session!.attempts.allSatisfy(\.assistanceUsed))
    }

    func testChangedSourceBlocksAssessmentBeforeCallingTutor() async {
        let tutor = TestLearningTutor()
        let vm = await start(tutor)
        vm.sourceIsCurrent = { _ in false }
        vm.answerDraft = "My answer"
        vm.submitAnswer()
        XCTAssertEqual(tutor.assessmentCount, 0)
        XCTAssertNotNil(vm.errorMessage)
    }

    func testSourceChangeDuringLessonGenerationRejectsLateTeachingWithoutSaving() async throws {
        let tutor = SuspendedLearningTutor()
        let vm = LearningViewModel { tutor }
        var writes = 0
        vm.onChange = { _ in writes += 1 }
        vm.start(source: learningSource)
        for _ in 0..<1_000 where tutor.continuation == nil { await Task.yield() }
        let pending = try XCTUnwrap(tutor.continuation)
        vm.sourceIsCurrent = { _ in false }
        pending.resume(returning: learningLesson())
        await vm.waitForOperation()
        XCTAssertTrue(vm.sessions.isEmpty)
        XCTAssertNil(vm.selectedSessionID)
        XCTAssertEqual(writes, 0)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isBusy)
    }

    func testSourceChangeDuringAssessmentPreservesDraftHelpHistoryAndSchedule() async throws {
        for phase in [LearningPhase.diagnostic, .practice, .exitCheck] {
            for delayed in [false, true] where !delayed || phase == .exitCheck {
                let tutor = SuspendedLearningTutor(); tutor.holdAssessment = true
                var original = LearningSession(source: learningSource, lesson: learningLesson(), phase: phase,
                    providerID: "original", modelID: nil)
                original.answerDraft = "Keep my unsent reasoning."
                original.sourceOpened = true
                original.attempts = [.init(phase: .diagnostic, question: original.lesson.diagnostic, answer: "An earlier answer",
                    assessment: assessment(.partial), assistanceUsed: true, providerID: "original", modelID: nil)]
                if delayed {
                    original.delayedReview = .init(previousSessionID: UUID(), scheduledFor: Date(), startedAt: Date(), round: 2, helpUsed: true)
                    original.reviewDueAt = Date().addingTimeInterval(86_400)
                }
                let vm = LearningViewModel { tutor }; vm.restore([original]); vm.select(original.id)
                var writes = 0; vm.onChange = { _ in writes += 1 }
                vm.submitAnswer()
                for _ in 0..<1_000 where tutor.assessmentContinuation == nil { await Task.yield() }
                let pending = try XCTUnwrap(tutor.assessmentContinuation)
                vm.sourceIsCurrent = { _ in false }
                pending.resume(returning: assessment(.correct))
                await vm.waitForOperation()
                XCTAssertEqual(vm.session, original)
                XCTAssertEqual(writes, 0)
                XCTAssertNotNil(vm.errorMessage)
                XCTAssertFalse(vm.isBusy)
            }
        }
    }

    func testSourceChangeWhilePreparingRetryKeepsOriginalQuestionAndPracticeFeedback() async throws {
        let tutor = SuspendedLearningTutor(); tutor.holdExitQuestion = true
        var original = LearningSession(source: learningSource, lesson: learningLesson(), phase: .practice,
            providerID: "original", modelID: nil)
        original.answerDraft = "A successful practice revision."
        original.feedback = assessment(.correct)
        original.hintsRevealed = 1
        original.attempts = [.init(phase: .exitCheck, question: original.lesson.exitCheck, answer: "Earlier exit reasoning",
            assessment: assessment(.incorrect), assistanceUsed: false, providerID: "original", modelID: nil)]
        let vm = LearningViewModel { tutor }; vm.restore([original]); vm.select(original.id)
        vm.advance()
        for _ in 0..<1_000 where tutor.questionContinuation == nil { await Task.yield() }
        let pending = try XCTUnwrap(tutor.questionContinuation)
        vm.sourceIsCurrent = { _ in false }
        pending.resume(returning: learningQuestion("A different independent problem"))
        await vm.waitForOperation()
        XCTAssertEqual(vm.session, original)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isBusy)
    }

    func testDelayedQuestionSourceChangeKeepsPriorEvidenceAndCanRecover() async throws {
        let tutor = SuspendedLearningTutor(); tutor.holdExitQuestion = true
        let unitID = UUID()
        let target = LearningStudyTarget(unitID: unitID, kind: .concept, objective: "Justify zero preservation.")
        let unit = LearningStudyUnit(id: unitID, title: "Linear maps", anchorPage: 0,
            sourceQuote: learningLesson().sourceQuote, pageIndices: [0], prerequisites: [],
            proofRequired: false, proofQuote: nil, gaps: [], targets: [target])
        var original = LearningSession(source: learningSource, lesson: learningLesson(), phase: .complete,
            providerID: "original", modelID: nil)
        original.studyTarget = target
        original.reviewDueAt = Date().addingTimeInterval(-86_400)
        var question = original.lesson.exitCheck; question.kind = .concept
        original.attempts = [.init(phase: .exitCheck, question: question, answer: "Earlier independent reasoning.",
            assessment: assessment(.correct), assistanceUsed: false, providerID: "original", modelID: nil)]
        let recommendation = LearningReviewRecommendation(unit: unit, target: target, previous: original,
            dueAt: original.reviewDueAt!, activeSessionID: nil)
        let vm = LearningViewModel { tutor }; vm.restore([original]); vm.select(original.id)
        var writes = 0; vm.onChange = { _ in writes += 1 }
        vm.startDelayedReview(recommendation)
        for _ in 0..<1_000 where tutor.questionContinuation == nil { await Task.yield() }
        let pending = try XCTUnwrap(tutor.questionContinuation)
        vm.sourceIsCurrent = { _ in false }
        pending.resume(returning: learningQuestion("A different delayed check: explain which linearity property preserves zero."))
        await vm.waitForOperation()
        XCTAssertEqual(vm.sessions, [original])
        XCTAssertEqual(writes, 0)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isBusy)
        // Returning to the current source can retry normally after rejection.
        vm.sourceIsCurrent = { _ in true }
        tutor.holdExitQuestion = false
        vm.startDelayedReview(recommendation); await vm.waitForOperation()
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.sessions.count, 2)
        XCTAssertEqual(vm.session?.delayedReview?.previousSessionID, original.id)
        XCTAssertEqual(vm.sessions.first { $0.id == original.id }, original)
    }

    func testDraftAndAssistanceArePersistedBeforeSubmitting() async {
        let tutor = TestLearningTutor()
        let vm = await start(tutor)
        var saved: [LearningSession] = []
        vm.onChange = { saved = $0 }
        vm.answerDraft = "A partial draft"
        vm.openedSource()
        XCTAssertEqual(saved.first?.answerDraft, "A partial draft")
        XCTAssertTrue(saved.first!.sourceOpened)
    }

    func testGenerationFailureDoesNotCreateEmptySession() async {
        let tutor = TestLearningTutor()
        tutor.shouldFail = true
        let vm = await start(tutor)
        XCTAssertTrue(vm.sessions.isEmpty)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isBusy)
    }

    func testCancellationDiscardsLateResultsAfterDocumentSwitch() async {
        let tutor = SuspendedLearningTutor()
        let vm = LearningViewModel { tutor }
        vm.start(source: learningSource)
        for _ in 0..<100 where tutor.continuation == nil { await Task.yield() }
        XCTAssertNotNil(tutor.continuation)
        vm.restore([])
        tutor.continuation?.resume(returning: learningLesson())
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(vm.sessions.isEmpty)
        XCTAssertFalse(vm.isBusy)
    }
}

@MainActor
private final class SuspendedLearningTutor: LearningTutorProtocol {
    let providerID = "suspended"
    let modelID: String? = nil
    var continuation: CheckedContinuation<LearningLesson, Never>?
    var holdAssessment = false
    var assessmentContinuation: CheckedContinuation<LearningAssessment, Never>?
    var holdExitQuestion = false
    var questionContinuation: CheckedContinuation<LearningQuestion, Never>?
    func makeLesson(source: LearningSource) async throws -> LearningLesson {
        await withCheckedContinuation { continuation = $0 }
    }
    func assess(question: LearningQuestion, answer: String, source: LearningSource) async throws -> LearningAssessment {
        if holdAssessment { return await withCheckedContinuation { assessmentContinuation = $0 } }
        return assessment(.uncertain)
    }
    func newExitQuestion(lesson: LearningLesson, source: LearningSource, previous: [String]) async throws -> LearningQuestion {
        if holdExitQuestion { return await withCheckedContinuation { questionContinuation = $0 } }
        return learningQuestion("Fresh question")
    }
}

@MainActor
final class LearningValidationTests: XCTestCase {
    func testPageRangeRejectsInvalidTextInsteadOfReusingAnOldValue() throws {
        XCTAssertEqual(try LearningSourceBuilder.pageRange(first: " 2 ", last: "7", pageCount: 20), 2...7)
        for (first, last) in [("", "2"), ("x", "2"), ("2", "1"), ("0", "1"), ("1", "7"), ("2", "21")] {
            XCTAssertThrowsError(try LearningSourceBuilder.pageRange(first: first, last: last, pageCount: 20))
        }
    }

    func testExitChecksRejectEmbeddedHints() {
        var lesson = learningLesson()
        lesson.exitCheck = learningQuestion("A new problem", hints: ["The answer is zero."])
        XCTAssertThrowsError(try LearningTutorService.validate(lesson, source: learningSource))
    }

    func testLegacyLearningSessionLoadsWithoutOutsideHelpField() throws {
        let session = LearningSession(source: learningSource, lesson: learningLesson(), providerID: "test", modelID: nil)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any])
        json.removeValue(forKey: "outsideHelpUsed")
        let decoded = try JSONDecoder().decode(LearningSession.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.outsideHelpUsed)
        XCTAssertFalse(decoded.assistanceUsed)
    }
    func testReferenceHoverSelectsTheReaderReferenceTab() {
        let engine = ContextEngineViewModel()
        let block = DocumentBlock(reference: .init(kind: .definition, number: "1"),
                                  formattedBody: "A definition", pageIndex: 0)
        engine.showReferencePreview(block: block)
        XCTAssertEqual(engine.selectedTab, .reference)
        XCTAssertEqual(engine.passiveBlock, block)
        engine.reset()
        engine.showReferencePreview(block: block)
        XCTAssertEqual(engine.selectedTab, .reference)
    }

    func testPortableReadingSessionRetainsLearningEvidence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let document = PDFDocument()
        let image = NSImage(size: NSSize(width: 100, height: 100), flipped: false) { _ in true }
        document.insert(PDFPage(image: image)!, at: 0)
        let pdf = root.appendingPathComponent("notes.pdf")
        XCTAssertTrue(document.write(to: pdf))
        let session = LearningSession(source: learningSource, lesson: learningLesson(), providerID: "test", modelID: nil)
        let workspace = DocumentWorkspace(documentURL: pdf, learningSessions: [session])
        let package = root.appendingPathComponent("notes.cauchyreading")
        try ReadingSessionPackageService.write(sourcePDF: pdf, destination: package, workspace: workspace)
        let (decoded, _) = try ReadingSessionPackageService.read(from: package)
        XCTAssertEqual(decoded.workspace.learningSessions.first?.lesson, session.lesson)
        XCTAssertEqual(decoded.workspace.learningSessions.first?.source, session.source)
        XCTAssertEqual(decoded.workspace.learningSessions.first?.providerID, "test")
    }

    func testRejectsObjectiveWithInventedSourceQuote() {
        let original = learningLesson()
        let invented = LearningLesson(title: original.title, objective: original.objective,
                                      sourceQuote: "The spectral theorem states that every matrix is diagonalizable.",
                                      explanation: original.explanation, workedExample: original.workedExample,
                                      diagnostic: original.diagnostic, practice: original.practice, exitCheck: original.exitCheck)
        XCTAssertThrowsError(try LearningTutorService.validate(invented, source: learningSource))
        XCTAssertNoThrow(try LearningTutorService.validate(original, source: learningSource))
    }

    func testQuoteCannotSpanPagesAndWhitespaceIsTolerated() {
        XCTAssertTrue(learningSource.contains(quote: "A linear map\npreserves addition and scalar multiplication."))
        let split = LearningSource(passages: [.init(pageIndex: 0, text: "An important mathematical statement"),
                                              .init(pageIndex: 1, text: "continues on another page.")])
        XCTAssertFalse(split.contains(quote: "An important mathematical statement continues on another page."))
    }

    func testParserPreservesLaTeXEscapesAndBracesInsideStrings() throws {
        let question = learningQuestion("Explain $\\frac{a}{b}$ and {a, b}.")
        let json = String(decoding: try JSONEncoder().encode(question), as: UTF8.self)
        let parsed: LearningQuestion = try LearningResponseParser.decode("Here is the question:\n```json\n\(json)\n```")
        XCTAssertEqual(parsed, question)
    }

    func testUnknownGradeCannotBecomeLearningEvidence() {
        XCTAssertThrowsError(try LearningResponseParser.decode("{\"grade\":\"mastered\",\"feedback\":\"great\",\"nextStep\":\"done\"}") as LearningAssessment)
    }

    func testLegacyWorkspaceLoadsWithoutLearningSessions() throws {
        let workspace = DocumentWorkspace(documentURL: URL(fileURLWithPath: "/tmp/notes.pdf"))
        let data = try JSONEncoder().encode(workspace)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "learningSessions")
        let decoded = try JSONDecoder().decode(DocumentWorkspace.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(decoded.learningSessions.isEmpty)
    }

    func testSavedWorkspaceRoundTripsDraftFeedbackAndAttempts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = DocumentPersistenceService(root: root)
        var session = LearningSession(source: learningSource, lesson: learningLesson(), providerID: "test", modelID: nil)
        session.answerDraft = "Unfinished reasoning"
        session.hintsRevealed = 1
        session.feedback = assessment(.partial)
        session.attempts = [.init(phase: .practice, question: session.lesson.practice, answer: "Attempt",
                                  assessment: assessment(.partial), assistanceUsed: true, providerID: "test", modelID: nil)]
        let workspace = DocumentWorkspace(documentURL: URL(fileURLWithPath: "/tmp/notes.pdf"), learningSessions: [session])
        try await persistence.saveWorkspace(workspace, bookmarkData: nil)
        let decoded = await persistence.loadWorkspace(id: workspace.id)
        XCTAssertEqual(decoded?.workspace.learningSessions.first?.answerDraft, "Unfinished reasoning")
        XCTAssertEqual(decoded?.workspace.learningSessions.first?.hintsRevealed, 1)
        XCTAssertEqual(decoded?.workspace.learningSessions.first?.attempts.first?.assessment.grade, .partial)
        XCTAssertEqual(decoded?.workspace.learningSessions.first?.feedback?.grade, .partial)
    }

    func testPageRangeOutsideDocumentAndImageOnlySourceAreRejected() {
        let document = PDFDocument()
        let image = NSImage(size: NSSize(width: 100, height: 100), flipped: false) { _ in true }
        document.insert(PDFPage(image: image)!, at: 0)
        XCTAssertThrowsError(try LearningSourceBuilder.pages(1...2, in: document))
        XCTAssertThrowsError(try LearningSourceBuilder.pages(1...1, in: document))
        XCTAssertFalse(LearningSourceBuilder.matches(learningSource, document: document))
    }
}

@MainActor
private final class ChapterTutorFixture: LearningTutorProtocol {
    let providerID = "authored-fixture"
    let modelID: String? = "local-test"
    var challenge: LearningChapterChallenge
    var delayAssessment = false
    var continuation: CheckedContinuation<LearningAssessment, Never>?
    var generationCalls = 0
    var delayGeneration = false
    var generationContinuation: CheckedContinuation<LearningChapterChallenge, Never>?
    init(_ challenge: LearningChapterChallenge) { self.challenge = challenge }
    func makeLesson(source: LearningSource) async throws -> LearningLesson { throw LearningError.invalidResponse }
    func makeChapterChallenge(request: LearningChapterRequest, source: LearningSource, previous: [String]) async throws -> LearningChapterChallenge {
        generationCalls += 1
        if delayGeneration { return await withCheckedContinuation { generationContinuation = $0 } }
        return challenge
    }
    func assess(question: LearningQuestion, answer: String, source: LearningSource) async throws -> LearningAssessment {
        let result = LearningAssessment(grade: .correct, feedback: "The subsequence argument uses both assumptions.",
            nextStep: "Explain where closedness is essential.", criteria: question.gradingCriteria?.indices.map {
                .init(index: $0, outcome: .met, feedback: "Justified by the corresponding step in the answer.")
            })
        if delayAssessment { return await withCheckedContinuation { continuation = $0 } }
        return result
    }
    func newExitQuestion(lesson: LearningLesson, source: LearningSource, previous: [String]) async throws -> LearningQuestion {
        throw LearningError.invalidResponse
    }
}

@MainActor
final class LearningChapterChallengeTests: XCTestCase {
    private func fixture() -> (LearningChapterRequest, LearningSource, LearningChapterChallenge) {
        let closed = "A closed subset of a sequentially compact metric space is sequentially compact."
        let image = "The image of a sequentially compact metric space under a continuous map is sequentially compact."
        let source = LearningSource(passages: [.init(pageIndex: 0, text: """
        A metric space is sequentially compact if every sequence has a subsequence converging to a point of the space.
        \(closed)
        Proof. A sequence in the closed subset K is a sequence in X. Choose a convergent subsequence in X. Closedness puts its limit in K.
        \(image)
        Proof. For a sequence of image points choose preimages. Sequential compactness gives a subsequence of preimages converging in the domain. Continuity makes the corresponding image subsequence converge to the image of that limit.
        A sequentially compact subspace of a metric space is closed and bounded: a missing closure point contradicts the subsequence property, and an unbounded sequence escaping every ball has no convergent subsequence.
        """)])
        let units = [closed, image].enumerated().map { index, quote -> LearningStudyUnit in
            let id = UUID(uuidString: index == 0 ? "11111111-1111-4111-8111-111111111111" : "22222222-2222-4222-8222-222222222222")!
            return .init(id: id, title: index == 0 ? "Closed subsets" : "Continuous images", anchorPage: 0,
                sourceQuote: quote, pageIndices: [0], prerequisites: ["Convergent subsequences"], proofRequired: true,
                proofQuote: quote, gaps: [], targets: [.init(unitID: id, kind: .proof, objective: "Justify this consequence")])
        }
        let request = LearningChapterRequest(moduleID: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!, title: "Sequential compactness",
            connection: "Use closedness to keep a subsequence limit in the domain before applying continuity.", units: units)
        let givens = "Let X be sequentially compact, K a closed subset of X, and f: X → Y continuous between metric spaces."
        let question = LearningQuestion(prompt: givens + " Prove that f(K) is sequentially compact.",
            expectedAnswer: "Choose any sequence in f(K) and preimages in K. Compactness of X gives a subsequence converging in X. Since K is closed, the limit lies in K. Continuity gives convergence of image points to its image in f(K).",
            hints: [], kind: .proof, gradingCriteria: ["Choose preimages in K", "Extract a subsequence and place its limit in K", "Apply continuity and conclude the image property"])
        let challenge = LearningChapterChallenge(moduleID: request.moduleID, title: "Carry a limit through a map", connection: request.connection,
            ideas: units.map { .init(unitID: $0.id, title: $0.title, pageIndex: 0, sourceQuote: $0.sourceQuote) },
            assumptions: [givens], question: question,
            criteria: [.init(index: 0, unitIDs: [units[1].id]), .init(index: 1, unitIDs: [units[0].id]), .init(index: 2, unitIDs: [units[1].id])],
            refresher: .init(unitID: units[0].id, pageIndex: 0, sourceQuote: closed,
                explanation: "A subsequence converges in X. Closedness of K is what puts its limit back in K.",
                check: .init(prompt: "Why must the limit of a convergent sequence in the closed subset K belong to K?",
                    expectedAnswer: "Closed subsets contain the limits in X of their convergent sequences.", hints: [], kind: .concept)))
        return (request, source, challenge)
    }

    func testSourceOrObligationChangesDuringChapterGenerationPreserveSavedWork() async throws {
        for fresh in [false, true] {
            for changedSource in [false, true] {
                let (request, source, challenge) = fixture()
                let tutor = ChapterTutorFixture(challenge)
                let vm = LearningViewModel { tutor }
                if fresh {
                    vm.startChapter(request: request, source: source); await vm.waitForOperation()
                    vm.answerDraft = "My original chapter reasoning."
                    vm.submitAnswer(); await vm.waitForOperation(); vm.advance()
                    tutor.challenge.question = .init(prompt: challenge.assumptions[0] + " Additionally Y is the real line. Prove that f(K) is closed and bounded.",
                        expectedAnswer: "Use the supplied image theorem and the closedness and boundedness consequence.",
                        hints: [], kind: .proof, gradingCriteria: challenge.question.gradingCriteria)
                }
                let original = vm.sessions
                var writes = 0; vm.onChange = { _ in writes += 1 }
                tutor.delayGeneration = true
                if fresh { vm.freshChapterCheck() } else { vm.startChapter(request: request, source: source) }
                for _ in 0..<1_000 where tutor.generationContinuation == nil { await Task.yield() }
                let pending = try XCTUnwrap(tutor.generationContinuation)
                if changedSource { vm.sourceIsCurrent = { _ in false } }
                else { vm.chapterRequestIsCurrent = { _ in false } }
                pending.resume(returning: tutor.challenge)
                await vm.waitForOperation()
                XCTAssertEqual(vm.sessions, original)
                XCTAssertEqual(writes, 0)
                XCTAssertNotNil(vm.errorMessage)
                XCTAssertFalse(vm.isBusy)
            }
        }
    }

    func testLateChapterAndRefresherGradesCannotApplyAfterSourceChange() async throws {
        for rescue in [false, true] {
            let (request, source, challenge) = fixture()
            let tutor = ChapterTutorFixture(challenge)
            let vm = LearningViewModel { tutor }
            vm.startChapter(request: request, source: source); await vm.waitForOperation()
            if rescue {
                vm.openPrerequisiteRescue()
                vm.rescueDraft = "Keep my refresher reasoning."
            } else { vm.answerDraft = "Keep my chapter reasoning." }
            let original = vm.session
            tutor.delayAssessment = true
            var writes = 0; vm.onChange = { _ in writes += 1 }
            vm.submitAnswer()
            for _ in 0..<1_000 where tutor.continuation == nil { await Task.yield() }
            let pending = try XCTUnwrap(tutor.continuation)
            let question = rescue ? challenge.refresher.check : challenge.question
            vm.sourceIsCurrent = { _ in false }
            pending.resume(returning: .init(grade: .correct, feedback: "A late result", nextStep: "Continue",
                criteria: question.gradingCriteria?.indices.map { .init(index: $0, outcome: .met, feedback: "An authored check") }))
            await vm.waitForOperation()
            XCTAssertEqual(vm.session, original)
            XCTAssertEqual(writes, 0)
            XCTAssertNotNil(vm.errorMessage)
            XCTAssertFalse(vm.isBusy)
        }
    }

    func testRescueReturnsToExactArgumentAndPersistsWithoutCredit() async throws {
        let (request, source, challenge) = fixture()
        let tutor = ChapterTutorFixture(challenge)
        let vm = LearningViewModel(makeTutor: { tutor })
        vm.startChapter(request: request, source: source)
        await vm.waitForOperation()
        let id = try XCTUnwrap(vm.session?.id)
        let question = try XCTUnwrap(vm.session?.question)
        vm.answerDraft = "Take a sequence in f(K) and choose preimages."
        vm.setChapterPosition("reasoning")
        vm.setChapterScrollOffset(317.25)
        vm.openPrerequisiteRescue()
        vm.setChapterScrollOffset(0) // The rescue must not move the underlying argument.
        vm.rescueDraft = "K is closed, so its convergent sequences have their limits in K."
        vm.submitAnswer()
        await vm.waitForOperation()
        XCTAssertTrue(vm.session?.attempts.isEmpty == true)
        XCTAssertEqual(vm.session?.chapter?.rescueAttempts.count, 1)
        XCTAssertTrue(vm.session?.assistanceUsed == true)

        // Restart while inside the rescue, retaining both drafts and navigation.
        let saved = try JSONEncoder().encode(vm.sessions)
        let restored = LearningViewModel(makeTutor: { tutor })
        restored.restore(try JSONDecoder().decode([LearningSession].self, from: saved))
        restored.select(id)
        XCTAssertTrue(restored.session?.chapter?.rescueVisible == true)
        XCTAssertEqual(restored.rescueDraft, "K is closed, so its convergent sequences have their limits in K.")
        XCTAssertEqual(restored.answerDraft, "Take a sequence in f(K) and choose preimages.")
        restored.returnToChapter()
        XCTAssertEqual(restored.session?.id, id)
        XCTAssertEqual(restored.session?.chapter?.position, "reasoning")
        XCTAssertEqual(restored.session?.chapter?.scrollOffset, 317.25)
        XCTAssertEqual(restored.session?.question, question)
        XCTAssertEqual(restored.answerDraft, "Take a sequence in f(K) and choose preimages.")
        restored.submitAnswer()
        await restored.waitForOperation()
        XCTAssertTrue(restored.session?.latestExitAttempt?.assistanceUsed == true)
        XCTAssertFalse(restored.session?.passedExitCheck == true)
        for unit in request.units {
            XCTAssertEqual(unit.checkedTargetCount(sessions: restored.sessions), 0)
            XCTAssertNil(unit.evidence(for: unit.targets[0], sessions: restored.sessions))
        }
    }

    func testFreshQuestionCanEarnIndependentChapterEvidenceOnly() async throws {
        let (request, source, challenge) = fixture()
        let tutor = ChapterTutorFixture(challenge)
        let vm = LearningViewModel(makeTutor: { tutor })
        vm.startChapter(request: request, source: source)
        await vm.waitForOperation()
        vm.openPrerequisiteRescue(); vm.returnToChapter()
        vm.answerDraft = "A complete assisted argument."
        vm.submitAnswer(); await vm.waitForOperation(); vm.advance()
        let id = vm.session?.id
        // Repeating the same question must not erase the help record.
        vm.freshChapterCheck(); await vm.waitForOperation()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.session?.assistanceUsed == true)
        var fresh = challenge
        fresh.question = .init(prompt: challenge.assumptions[0] + " Additionally Y is the real line. Prove that f(K) is closed and bounded.",
            expectedAnswer: "Closedness of K makes it sequentially compact. Its continuous image is sequentially compact and hence closed and bounded by the supplied consequence.",
            hints: [], kind: .proof, gradingCriteria: challenge.question.gradingCriteria)
        tutor.challenge = fresh
        vm.freshChapterCheck(); await vm.waitForOperation()
        XCTAssertEqual(vm.session?.id, id)
        XCTAssertFalse(vm.session?.assistanceUsed == true)
        vm.answerDraft = "A complete new unassisted argument."
        vm.submitAnswer(); await vm.waitForOperation()
        XCTAssertTrue(vm.session?.passedExitCheck == true)
        XCTAssertEqual(vm.session?.attempts.count, 2)
        XCTAssertTrue(vm.session?.attempts.first?.assistanceUsed == true)
        XCTAssertEqual(request.units.reduce(0) { $0 + $1.checkedTargetCount(sessions: vm.sessions) }, 0)
        var wronglyAttached = try XCTUnwrap(vm.session)
        wronglyAttached.studyTarget = request.units[0].targets[0]
        XCTAssertNil(request.units[0].evidence(for: request.units[0].targets[0], sessions: [wronglyAttached]))
        vm.advance()
        vm.chapterRequestIsCurrent = { _ in false }
        let calls = tutor.generationCalls
        vm.freshChapterCheck()
        XCTAssertEqual(tutor.generationCalls, calls)
        XCTAssertNotNil(vm.errorMessage)
    }

    func testSourceGapsBlockBeforeGenerationAndDoNotBecomeRescue() async throws {
        let (request, source, challenge) = fixture()
        let unit = request.units[0]
        let blocked = LearningStudyUnit(id: unit.id, title: unit.title, anchorPage: 0, sourceQuote: unit.sourceQuote,
            pageIndices: [0], prerequisites: [], proofRequired: true, proofQuote: nil,
            gaps: ["The proof is explicitly omitted."], targets: unit.targets)
        let invalid = LearningChapterRequest(moduleID: request.moduleID, title: request.title, connection: request.connection,
            units: [blocked, request.units[1]])
        let tutor = ChapterTutorFixture(challenge)
        let vm = LearningViewModel(makeTutor: { tutor })
        vm.startChapter(request: invalid, source: source)
        XCTAssertEqual(tutor.generationCalls, 0)
        XCTAssertTrue(vm.sessions.isEmpty)
        XCTAssertNotNil(vm.errorMessage)
        let module = LearningCourse.Module(id: request.moduleID, title: request.title, goal: "Connect the results", unitIDs: invalid.units.map(\.id))
        let map = LearningStudyMap(pageSignatures: [], pages: [], units: invalid.units,
            course: .init(title: "Course", overview: "Overview", modules: [module], connections: [.init(fromUnitID: unit.id, toUnitID: request.units[1].id, reason: request.connection)]))
        XCTAssertNil(map.chapterRequest(for: module))
    }

    func testLateRescueAssessmentCannotOverwriteReturnedArgument() async throws {
        let (request, source, challenge) = fixture()
        let tutor = ChapterTutorFixture(challenge)
        let vm = LearningViewModel(makeTutor: { tutor })
        vm.startChapter(request: request, source: source); await vm.waitForOperation()
        vm.answerDraft = "Original argument"
        vm.openPrerequisiteRescue(); vm.rescueDraft = "Rescue draft"
        tutor.delayAssessment = true
        vm.submitAnswer()
        for _ in 0..<100 where tutor.continuation == nil { await Task.yield() }
        let continuation = try XCTUnwrap(tutor.continuation)
        vm.returnToChapter()
        continuation.resume(returning: .init(grade: .incorrect, feedback: "Late feedback", nextStep: "Ignored"))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(vm.answerDraft, "Original argument")
        XCTAssertNil(vm.session?.feedback)
        XCTAssertNil(vm.session?.chapter?.rescueFeedback)
        XCTAssertTrue(vm.session?.attempts.isEmpty == true)
        XCTAssertFalse(vm.isBusy)
    }

    func testRejectsUnrelatedCriteriaMissingHypothesesAndFalseCitations() throws {
        let (request, source, challenge) = fixture()
        try LearningTutorService.validate(challenge, request: request, source: source)
        let encoder = JSONEncoder()
        func changed(_ mutate: (inout [String: Any]) -> Void) throws -> LearningChapterChallenge {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(challenge)) as? [String: Any])
            mutate(&json)
            return try JSONDecoder().decode(LearningChapterChallenge.self, from: JSONSerialization.data(withJSONObject: json))
        }
        let unrelated = try changed { $0["criteria"] = [["index": 0, "unitIDs": [UUID().uuidString]], ["index": 1, "unitIDs": [request.units[0].id.uuidString]], ["index": 2, "unitIDs": [request.units[1].id.uuidString]]] }
        XCTAssertThrowsError(try LearningTutorService.validate(unrelated, request: request, source: source))
        let missing = try changed { $0["assumptions"] = ["K is not assumed closed here."] }
        XCTAssertThrowsError(try LearningTutorService.validate(missing, request: request, source: source))
        let citation = try changed { json in
            var ideas = json["ideas"] as! [[String: Any]]
            ideas[0]["pageIndex"] = 42
            json["ideas"] = ideas
        }
        XCTAssertThrowsError(try LearningTutorService.validate(citation, request: request, source: source))
        let duplicate = LearningAssessment(grade: .correct, feedback: "Complete", nextStep: "Continue", criteria: [
            .init(index: 0, outcome: .met, feedback: "Evidence"), .init(index: 0, outcome: .met, feedback: "Evidence"), .init(index: 2, outcome: .met, feedback: "Evidence")])
        XCTAssertThrowsError(try LearningTutorService.checkedAssessment(duplicate, question: challenge.question))
        let uncertain = LearningAssessment(grade: .correct, feedback: "One step cannot be checked", nextStep: "Review the step", criteria: [
            .init(index: 0, outcome: .met, feedback: "Evidence"), .init(index: 1, outcome: .uncertain, feedback: "Unclear"), .init(index: 2, outcome: .met, feedback: "Evidence")])
        XCTAssertEqual(try LearningTutorService.checkedAssessment(uncertain, question: challenge.question).grade, .uncertain)
    }

    func testLiveAuthoredChapterGenerationPassesSourceAndCriterionValidator() throws {
        struct Fixture: Decodable { let request: LearningChapterRequest; let source: LearningSource }
        struct Results: Decodable { let generation: LearningChapterChallenge }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appendingPathComponent("docs/evaluation/chapter-challenge-fixture.json")))
        let result = try JSONDecoder().decode(Results.self, from: Data(contentsOf: root.appendingPathComponent("docs/evaluation/chapter-challenge-results.json")))
        try LearningTutorService.validate(result.generation, request: fixture.request, source: fixture.source)
    }

    func testNewChallengePersistencePreservesExistingSessionIDsAndAnnotations() async throws {
        let (request, source, challenge) = fixture()
        let tutor = ChapterTutorFixture(challenge)
        let vm = LearningViewModel(makeTutor: { tutor })
        var old = LearningSession(source: source, lesson: learningLesson(), providerID: "old", modelID: nil)
        old.createdAt = Date(timeIntervalSince1970: 1_711_111_111)
        old.updatedAt = old.createdAt
        vm.restore([old])
        vm.startChapter(request: request, source: source); await vm.waitForOperation()
        vm.answerDraft = "Unsent proof"
        vm.openPrerequisiteRescue(); vm.rescueDraft = "Unsent prerequisite"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = DocumentPersistenceService(root: root)
        var workspace = DocumentWorkspace(documentURL: URL(fileURLWithPath: "/tmp/authored-chapter.pdf"))
        workspace.highlights = [.init(pageIndex: 0, selectedText: "Retain this annotation", note: "Reader note",
            createdAt: old.createdAt, updatedAt: old.updatedAt)]
        workspace.learningSessions = vm.sessions
        workspace.learningSessions[0].createdAt = Date(timeIntervalSince1970: 1_711_111_112.25)
        workspace.learningSessions[0].updatedAt = Date(timeIntervalSince1970: 1_711_111_113.75)
        try await persistence.saveWorkspace(workspace, bookmarkData: nil, learningOnly: true)
        let loaded = await persistence.loadWorkspace(id: workspace.id)
        XCTAssertEqual(loaded?.workspace.learningSessions, workspace.learningSessions)
        XCTAssertEqual(loaded?.workspace.highlights, workspace.highlights)
        XCTAssertEqual(loaded?.workspace.learningSessions.last, old)
        // A legacy object has no chapter key, and retains its exact identity.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        json.removeValue(forKey: "chapter")
        let legacy = try JSONDecoder().decode(LearningSession.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(legacy, old)
    }
}

@MainActor
final class LearningProviderReadinessTests: XCTestCase {
    func testLearnRequestsRecordSuccessAndFailureForTheirCapturedModelOnly() async throws {
        let suite = "LearningProviderReadinessTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProviderReadinessStore(defaults: defaults,
            binaryIsInstalled: { _ in true }, apiKeyIsStored: { _ in true })
        let resolved = ResolvedAssistant(connector: AssistantConnectorID.codex.connector,
            choice: .model("captured-model"), viaAutomatic: false)
        XCTAssertEqual(store.state(for: .codex, modelID: resolved.modelID), .unknown)
        let result = try await LearningTutorService.providerRequest(resolved: resolved, readiness: store) { "OK" }
        XCTAssertEqual(result, "OK")
        XCTAssertEqual(store.state(for: .codex, modelID: resolved.modelID), .ready)
        XCTAssertEqual(store.state(for: .codex, modelID: "different-model"), .unknown)
        do {
            let _: String = try await LearningTutorService.providerRequest(resolved: resolved, readiness: store) {
                throw AssistantFailure.notSignedIn(.codex)
            }
            XCTFail("Expected provider failure")
        } catch {
            XCTAssertEqual(error as? AssistantFailure, .notSignedIn(.codex))
        }
        XCTAssertEqual(store.state(for: .codex, modelID: resolved.modelID), .blocked(.notSignedIn(.codex)))
        XCTAssertEqual(store.state(for: .codex, modelID: "different-model"), .unknown)
    }

    func testCancelledLearnRequestDoesNotMarkUnknownProviderReadyOrBlockCachedSuccess() async throws {
        let suite = "LearningProviderReadinessTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProviderReadinessStore(defaults: defaults,
            binaryIsInstalled: { _ in true }, apiKeyIsStored: { _ in true })
        let resolved = ResolvedAssistant(connector: AssistantConnectorID.codex.connector,
            choice: .model("captured-model"), viaAutomatic: false)
        for ready in [false, true] {
            if ready { store.markReady(connectorID: .codex, modelID: resolved.modelID) }
            do {
                let _: String = try await LearningTutorService.providerRequest(resolved: resolved, readiness: store) {
                    throw CancellationError()
                }
                XCTFail("Expected cancellation")
            } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertEqual(store.state(for: .codex, modelID: resolved.modelID), ready ? .ready : .unknown)
        }
    }
}
