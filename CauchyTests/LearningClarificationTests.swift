import XCTest
@testable import Cauchy

@MainActor
private final class ClarificationTutor: LearningTutorProtocol {
    let providerID = "clarification-test"
    let modelID: String? = "test-model"
    var failure = false
    var hold = false
    var continuation: CheckedContinuation<LearningClarificationReply, Never>?
    var received: [LearningClarification] = []
    var calls = 0
    var reply = LearningClarificationReply(answer: "Use the stated hypothesis to justify the step.", basis: .suppliedNotes,
        citations: [.init(pageIndex: 0, quote: "A linear map preserves addition and scalar multiplication.")])

    func clarify(question: String, context: LearningClarificationContext, source: LearningSource,
                 previous: [LearningClarification]) async throws -> LearningClarificationReply {
        calls += 1
        received = previous
        if failure { throw LearningError.invalidResponse }
        if hold { return await withCheckedContinuation { continuation = $0 } }
        return reply
    }
    func makeLesson(source: LearningSource) async throws -> LearningLesson { throw LearningError.invalidResponse }
    func assess(question: LearningQuestion, answer: String, source: LearningSource) async throws -> LearningAssessment {
        .init(grade: .correct, feedback: "Authored assessment.", nextStep: "Continue.")
    }
    func newExitQuestion(lesson: LearningLesson, source: LearningSource, previous: [String]) async throws -> LearningQuestion {
        throw LearningError.invalidResponse
    }
}

@MainActor
final class LearningClarificationTests: XCTestCase {
    private let source = LearningSource(passages: [.init(pageIndex: 0,
        text: "A linear map preserves addition and scalar multiplication. Its kernel consists of the vectors sent to zero.")])

    private func saved(phase: LearningPhase = .lesson) -> LearningSession {
        let question = LearningQuestion(prompt: "Why is the zero vector sent to zero?", expectedAnswer: "PRIVATE ANSWER KEY", hints: ["Use the scalar zero."])
        let lesson = LearningLesson(title: "Linear maps", objective: "Justify the zero-vector property.",
            sourceQuote: "A linear map preserves addition and scalar multiplication.", explanation: "Use scalar multiplication with zero.",
            workedExample: "Multiply a matrix by the zero vector.", diagnostic: question, practice: question,
            exitCheck: .init(prompt: "Can a translation be linear?", expectedAnswer: "EXIT ANSWER KEY", hints: []))
        var session = LearningSession(source: source, lesson: lesson, providerID: "old-provider", modelID: "old-model")
        session.phase = phase
        session.answerDraft = "My original reasoning."
        return session
    }

    private func model(_ session: LearningSession, tutor: ClarificationTutor) -> LearningViewModel {
        let vm = LearningViewModel { tutor }
        vm.restore([session]); vm.select(session.id)
        return vm
    }

    func testContextContainsOnlyCurrentTeachingOrQuestionWithoutAnswerKeys() throws {
        var session = saved()
        let idea = try XCTUnwrap(session.clarificationContext)
        XCTAssertTrue(idea.content.contains(session.lesson.explanation))
        XCTAssertFalse(idea.content.contains(session.lesson.workedExample))
        session.lessonPartIndex = 1
        let example = try XCTUnwrap(session.clarificationContext)
        XCTAssertNotEqual(idea.id, example.id)
        session.phase = .exitCheck
        let question = try XCTUnwrap(session.clarificationContext)
        XCTAssertEqual(question.content, session.lesson.exitCheck.prompt)
        XCTAssertFalse(question.content.contains("ANSWER KEY"))
        session.lesson.exitCheck = .init(prompt: "A genuinely different fresh question", expectedAnswer: "key", hints: [])
        XCTAssertNotEqual(session.clarificationContext?.id, question.id)
        session.phase = .complete
        XCTAssertNil(session.clarificationContext)
    }

    func testPerStepDraftsAndLegacySessionsDecodeWithoutChangingPositionOrAnswer() throws {
        let tutor = ClarificationTutor()
        let original = saved()
        let vm = model(original, tutor: tutor)
        let idea = try XCTUnwrap(vm.session?.clarificationContext)
        vm.setClarificationDraft("Why this hypothesis?", for: idea)
        vm.selectLessonPart(1)
        let example = try XCTUnwrap(vm.session?.clarificationContext)
        vm.setClarificationDraft(String(repeating: "x", count: 2_500), for: example)
        XCTAssertEqual(vm.clarificationDraft(for: example).count, 2_000)
        vm.setClarificationDraft("Do not overwrite another part", for: idea)
        let decoded = try JSONDecoder().decode(LearningSession.self, from: JSONEncoder().encode(vm.session!))
        XCTAssertEqual(decoded.currentLessonPartIndex, 1)
        XCTAssertEqual(decoded.answerDraft, original.answerDraft)
        vm.restore([decoded]); vm.select(decoded.id)
        XCTAssertEqual(vm.clarificationDraft(for: idea), "Why this hypothesis?")
        XCTAssertEqual(vm.clarificationDraft(for: example).count, 2_000)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
        for field in ["clarifications", "clarificationDrafts", "clarificationHelpUsed"] { json.removeValue(forKey: field) }
        let legacy = try JSONDecoder().decode(LearningSession.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(legacy.clarifications)
        XCTAssertNil(legacy.clarificationDrafts)
        XCTAssertNil(legacy.clarificationHelpUsed)
    }

    func testReplyPreservesLessonAndRecordsExactContextProvenanceAndBoundedHistory() async throws {
        let tutor = ClarificationTutor()
        var original = saved()
        original.lessonPartIndex = 1
        let vm = model(original, tutor: tutor)
        let context = try XCTUnwrap(vm.session?.clarificationContext)
        for index in 0..<4 {
            vm.setClarificationDraft("Question \(index)", for: context)
            vm.askClarification(for: context); await vm.waitForOperation()
        }
        let session = try XCTUnwrap(vm.session)
        let exchanges = try XCTUnwrap(session.clarifications)
        XCTAssertEqual(exchanges.count, 4)
        XCTAssertEqual(tutor.received.map(\.id), Array(exchanges[1...2]).map(\.id))
        XCTAssertEqual(exchanges.last?.previousExchangeIDs, tutor.received.map(\.id))
        XCTAssertEqual(exchanges.last?.suppliedPageIndices, [0])
        XCTAssertEqual(exchanges.last?.providerID, "clarification-test")
        XCTAssertEqual(exchanges.last?.modelID, "test-model")
        XCTAssertEqual(exchanges.last?.context, context)
        XCTAssertEqual(session.lesson, original.lesson)
        XCTAssertEqual(session.source, original.source)
        XCTAssertEqual(session.answerDraft, original.answerDraft)
        XCTAssertEqual(session.currentLessonPartIndex, 1)
        XCTAssertTrue(session.attempts.isEmpty)
        XCTAssertFalse(session.passedExitCheck)
        XCTAssertFalse(session.assistanceUsed)
        XCTAssertEqual(vm.clarificationDraft(for: context), "")
    }

    func testCurrentAssessmentReplyAndReopeningHistoryCannotEarnIndependentCredit() async throws {
        let tutor = ClarificationTutor()
        let vm = model(saved(phase: .exitCheck), tutor: tutor)
        let context = try XCTUnwrap(vm.session?.clarificationContext)
        vm.openedClarifications(for: context)
        XCTAssertFalse(vm.session!.assistanceUsed)
        vm.setClarificationDraft("Explain this question.", for: context)
        vm.askClarification(for: context); await vm.waitForOperation()
        XCTAssertTrue(vm.session!.clarificationHelpUsed == true)
        vm.outsideHelpUsed = false
        vm.submitAnswer(); await vm.waitForOperation()
        XCTAssertEqual(vm.session?.attempts.last?.assessment.grade, .correct)
        XCTAssertTrue(vm.session?.attempts.last?.assistanceUsed == true)
        XCTAssertFalse(vm.session!.passedExitCheck)
        let calls = tutor.calls
        let afterAssessment = vm.session
        vm.setClarificationDraft("A new question after this answer was assessed", for: context)
        vm.askClarification(for: context)
        vm.openedClarifications(for: context)
        XCTAssertEqual(tutor.calls, calls)
        XCTAssertEqual(vm.session, afterAssessment)
        // Reopening an already completed result does not rewrite its evidence.
        vm.advance()
        let attempts = vm.session!.attempts
        vm.openedClarifications(for: context)
        XCTAssertEqual(vm.session?.attempts, attempts)
    }

    func testPracticeRevisionKeepsHelpButNewIndependentQuestionStartsFresh() async throws {
        let tutor = ClarificationTutor()
        let vm = model(saved(phase: .practice), tutor: tutor)
        let context = try XCTUnwrap(vm.session?.clarificationContext)
        vm.setClarificationDraft("Why?", for: context)
        vm.askClarification(for: context); await vm.waitForOperation()
        vm.submitAnswer(); await vm.waitForOperation(); vm.tryAgain()
        XCTAssertTrue(vm.session!.assistanceUsed)
        vm.submitAnswer(); await vm.waitForOperation(); vm.advance()
        XCTAssertEqual(vm.session?.phase, .exitCheck)
        XCTAssertFalse(vm.session!.assistanceUsed)
        // Opening a saved explanation while answering marks help again.
        vm.openedClarifications(for: context)
        XCTAssertTrue(vm.session!.assistanceUsed)
    }

    func testFailureAndCancellationRetainDraftWithoutFabricatingReplyOrHelp() async throws {
        let tutor = ClarificationTutor()
        tutor.failure = true
        let original = saved(phase: .practice)
        let vm = model(original, tutor: tutor)
        let context = try XCTUnwrap(vm.session?.clarificationContext)
        vm.setClarificationDraft("Keep this question.", for: context)
        vm.askClarification(for: context); await vm.waitForOperation()
        XCTAssertNotNil(vm.clarificationErrorMessage)
        XCTAssertNil(vm.errorMessage)
        XCTAssertNil(vm.session?.clarifications)
        XCTAssertEqual(vm.answerDraft, original.answerDraft)
        XCTAssertFalse(vm.session!.assistanceUsed)
        tutor.failure = false; tutor.hold = true
        vm.askClarification(for: context)
        for _ in 0..<1_000 {
            if tutor.continuation != nil { break }
            await Task.yield()
        }
        _ = try XCTUnwrap(tutor.continuation)
        vm.cancelClarification()
        let completion = tutor.continuation
        tutor.continuation = nil
        completion?.resume(returning: tutor.reply)
        await Task.yield()
        XCTAssertNil(vm.session?.clarifications)
        XCTAssertEqual(vm.clarificationDraft(for: context), "Keep this question.")
        XCTAssertFalse(vm.session!.assistanceUsed)
        XCTAssertFalse(vm.isBusy)
    }

    func testSourceChangesBlockBothNewRequestAndLateReply() async throws {
        let tutor = ClarificationTutor()
        let vm = model(saved(), tutor: tutor)
        let context = try XCTUnwrap(vm.session?.clarificationContext)
        vm.setClarificationDraft("Why?", for: context)
        vm.sourceIsCurrent = { _ in false }
        vm.askClarification(for: context)
        XCTAssertEqual(tutor.calls, 0)
        XCTAssertNotNil(vm.clarificationErrorMessage)
        tutor.hold = true
        vm.sourceIsCurrent = { _ in true }
        vm.askClarification(for: context)
        for _ in 0..<1_000 {
            if tutor.continuation != nil { break }
            await Task.yield()
        }
        _ = try XCTUnwrap(tutor.continuation)
        vm.sourceIsCurrent = { _ in false }
        tutor.continuation?.resume(returning: tutor.reply); tutor.continuation = nil
        await vm.waitForOperation()
        XCTAssertNil(vm.session?.clarifications)
        XCTAssertEqual(vm.clarificationDraft(for: context), "Why?")
        XCTAssertNotNil(vm.clarificationErrorMessage)
    }

    func testDelayedHelpPersistsAndHistoricalContextCannotRequestNewTeaching() async throws {
        let tutor = ClarificationTutor()
        var original = saved(phase: .exitCheck)
        original.delayedReview = .init(previousSessionID: UUID(), scheduledFor: Date(), startedAt: Date(), round: 1)
        let vm = model(original, tutor: tutor)
        let context = try XCTUnwrap(vm.session?.clarificationContext)
        vm.setClarificationDraft("Explain the hypothesis.", for: context)
        vm.askClarification(for: context); await vm.waitForOperation()
        XCTAssertTrue(vm.session?.delayedReview?.helpUsed == true)
        vm.submitAnswer(); await vm.waitForOperation(); vm.advance(); vm.practiseAgain()
        XCTAssertTrue(vm.session!.assistanceUsed)
        let count = tutor.calls
        vm.setClarificationDraft("Do not attach a new draft to the earlier check.", for: context)
        vm.askClarification(for: context)
        XCTAssertEqual(tutor.calls, count)
        XCTAssertEqual(vm.clarificationDraft(for: context), "")
        XCTAssertEqual(vm.session?.clarifications?.count, 1)
    }

    func testInvalidProviderCitationPreservesQuestionWithoutExposingNewHelp() async throws {
        let tutor = ClarificationTutor()
        tutor.reply.citations = [.init(pageIndex: 900, quote: "An invented quotation with a false page reference.")]
        let vm = model(saved(phase: .practice), tutor: tutor)
        let context = try XCTUnwrap(vm.session?.clarificationContext)
        vm.setClarificationDraft("Question with a failed source check.", for: context)
        vm.askClarification(for: context); await vm.waitForOperation()
        XCTAssertNil(vm.session?.clarifications)
        XCTAssertFalse(vm.session!.assistanceUsed)
        XCTAssertEqual(vm.clarificationDraft(for: context), "Question with a failed source check.")
        XCTAssertTrue(vm.clarificationErrorMessage?.contains("source reference") == true)
        XCTAssertNil(vm.errorMessage)
    }

    func testCitationValidationRejectsFalseLocationsAndBindsCorrectionProvenance() throws {
        let tutor = ClarificationTutor()
        XCTAssertNoThrow(try LearningTutorService.checkedClarification(tutor.reply, source: source))
        var missing = tutor.reply
        missing.citations = []
        XCTAssertThrowsError(try LearningTutorService.checkedClarification(missing, source: source))
        var wrong = tutor.reply
        wrong.citations = [.init(pageIndex: 1, quote: source.passages[0].text)]
        XCTAssertThrowsError(try LearningTutorService.checkedClarification(wrong, source: source))
        wrong.citations = [.init(pageIndex: 0, quote: "An invented source quote that is not on this page.")]
        XCTAssertThrowsError(try LearningTutorService.checkedClarification(wrong, source: source))
        let correction = LearningSourceCorrection(pageIndex: 0, originalText: "damaged original", correctedText: source.passages[0].text, note: "Compared with PDF", previousID: nil)
        let revised = LearningSource(passages: [.init(pageIndex: 0, text: correction.correctedText, correction: correction)])
        wrong = tutor.reply
        wrong.citations[0].correctionID = UUID()
        let checked = try LearningTutorService.checkedClarification(wrong, source: revised)
        XCTAssertEqual(checked.citations[0].correctionID, correction.id)
        XCTAssertNil(try LearningTutorService.checkedClarification(wrong, source: source).citations[0].correctionID)
        XCTAssertNoThrow(try LearningTutorService.checkedClarification(.init(answer: "The supplied source cannot establish this claim.", basis: .insufficientSource, citations: []), source: source))
        XCTAssertThrowsError(try LearningTutorService.checkedClarification(.init(answer: String(repeating: "x", count: 6_001), basis: .additionalExplanation, citations: []), source: source))
    }

    func testRecordedLiveClarificationsPassProductionSourceValidator() throws {
        struct Run: Decodable {
            struct Case: Decodable {
                let source: String
                let reply: LearningClarificationReply
                let expectedBasis: [String]
            }
            let results: [Case]
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let run = try JSONDecoder().decode(Run.self, from: Data(contentsOf: root.appendingPathComponent("docs/evaluation/learning-clarification-results.json")))
        XCTAssertEqual(run.results.count, 3)
        for item in run.results {
            let source = LearningSource(passages: [.init(pageIndex: 0, text: item.source)])
            let checked = try LearningTutorService.checkedClarification(item.reply, source: source)
            XCTAssertTrue(item.expectedBasis.contains(checked.basis.rawValue))
        }
    }

#if DEBUG
    func testClarificationAndUnsentFollowupSurviveRealFixturePersistenceRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cauchy-ui-fixture-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = LearningUIFixtureController(rootPath: root.path)
        await controller.load()
        let document = try XCTUnwrap(controller.library?.selectedDocument)
        let id = try XCTUnwrap(document.learning.sessions.first?.id)
        document.learning.select(id)
        let context = try XCTUnwrap(document.learning.session?.clarificationContext)
        let originalAnswer = document.learning.answerDraft
        document.learning.setClarificationDraft("What does this hypothesis do?", for: context)
        document.learning.askClarification(for: context); await document.learning.waitForOperation()
        document.learning.setClarificationDraft("Unsent follow-up", for: context)
        let expected = try XCTUnwrap(document.learning.session)
        try await controller.flush()
        let restart = LearningUIFixtureController(rootPath: root.path)
        await restart.load()
        let restored = try XCTUnwrap(restart.library?.selectedDocument)
        restored.learning.select(id)
        // Compare every field in the learning sidecar's actual epoch-based
        // date format, avoiding Date's reference-epoch rounding difference.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try encoder.encode(restored.learning.session), try encoder.encode(expected))
        XCTAssertEqual(restored.learning.answerDraft, originalAnswer)
        XCTAssertEqual(restored.learning.clarificationDraft(for: context), "Unsent follow-up")
        XCTAssertTrue(restored.learning.session?.clarificationHelpUsed == true)
        XCTAssertEqual(restored.learning.session?.clarifications?.count, 1)
        XCTAssertTrue(restored.learning.session!.attempts.isEmpty)
    }
#endif
}
