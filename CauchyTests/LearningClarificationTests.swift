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

    private func assessed(grade: LearningGrade = .partial, delayed: Bool = false) -> LearningSession {
        var session = saved(phase: .exitCheck)
        session.lesson.exitCheck.gradingCriteria = ["Justify the limit location."]
        let assessment = LearningAssessment(grade: grade, feedback: "The hypothesis needs justification.", nextStep: "Explain where the limit belongs.",
            criteria: [.init(index: 0, outcome: grade == .correct ? .met : .uncertain, feedback: "Connect the limit to the stated hypothesis.")])
        session.attempts = [.init(phase: .exitCheck, question: session.lesson.exitCheck, answer: "My assessed argument.",
            assessment: assessment, assistanceUsed: false, providerID: "original", modelID: "original-model")]
        session.feedback = assessment
        session.answerDraft = session.attempts[0].answer
        if delayed {
            session.delayedReview = .init(previousSessionID: UUID(), scheduledFor: Date(), startedAt: Date(), round: 1)
            session.reviewDueAt = Date().addingTimeInterval(86_400)
        }
        return session
    }

    func testFeedbackContextBindsExactAttemptAndOmitsKeysAcrossResultNavigation() throws {
        var session = assessed()
        let context = try XCTUnwrap(session.feedbackClarificationContext)
        XCTAssertEqual(context.attemptID, session.attempts[0].id)
        XCTAssertTrue(context.content.contains(session.attempts[0].question.prompt))
        XCTAssertTrue(context.content.contains(session.attempts[0].answer))
        XCTAssertTrue(context.content.contains(session.attempts[0].assessment.feedback))
        XCTAssertTrue(context.content.contains(session.attempts[0].assessment.nextStep))
        XCTAssertTrue(context.content.contains("Justify the limit location."))
        XCTAssertTrue(context.content.contains("Connect the limit to the stated hypothesis."))
        XCTAssertFalse(context.content.contains("ANSWER KEY"))
        XCTAssertNotEqual(context.id, session.clarificationContext?.id)
        session.move(to: .complete)
        XCTAssertEqual(session.feedbackClarificationContext, context)
        session.attempts[0].id = UUID()
        XCTAssertNotEqual(session.feedbackClarificationContext?.id, context.id)
        let originalQuestion = try XCTUnwrap(saved(phase: .practice).clarificationContext)
        let legacy = try JSONDecoder().decode(LearningClarificationContext.self, from: JSONEncoder().encode(originalQuestion))
        XCTAssertNil(legacy.attemptID)
        XCTAssertEqual(legacy.id, originalQuestion.id)
    }

    func testFeedbackDiscussionPreservesEveryGradeAndAssistanceIncludingDelayedEvidence() async throws {
        for grade in [LearningGrade.correct, .partial, .incorrect, .uncertain] {
            for delayed in [false, true] {
                let tutor = ClarificationTutor()
                let original = assessed(grade: grade, delayed: delayed)
                let vm = model(original, tutor: tutor)
                let context = try XCTUnwrap(vm.session?.feedbackClarificationContext)
                vm.setClarificationDraft("Why this feedback?", for: context)
                vm.askClarification(for: context); await vm.waitForOperation()
                vm.openedClarifications(for: context)
                let result = try XCTUnwrap(vm.session)
                XCTAssertEqual(result.attempts, original.attempts)
                XCTAssertEqual(result.feedback, original.feedback)
                XCTAssertEqual(result.answerDraft, original.answerDraft)
                XCTAssertEqual(result.assistanceUsed, original.assistanceUsed)
                XCTAssertEqual(result.delayedReview, original.delayedReview)
                XCTAssertEqual(result.reviewDueAt, original.reviewDueAt)
                XCTAssertEqual(result.passedExitCheck, original.passedExitCheck)
                XCTAssertEqual(result.lesson, original.lesson)
                XCTAssertEqual(result.clarifications?.last?.context, context)
                XCTAssertEqual(result.clarifications?.last?.question, "Why this feedback?")
                XCTAssertFalse(vm.isBusy)
            }
        }
    }

    func testHistoricalFeedbackStaysReadOnlyAndViewingItDuringAnotherAnswerRecordsHelp() async throws {
        let tutor = ClarificationTutor()
        var original = assessed()
        original.phase = .practice
        original.lesson.practice = original.attempts[0].question
        let old = original.attempts[0]
        original.attempts = [.init(phase: .practice, question: old.question, answer: old.answer, assessment: old.assessment,
            assistanceUsed: false, providerID: old.providerID, modelID: old.modelID)]
        let vm = model(original, tutor: tutor)
        let context = try XCTUnwrap(vm.session?.feedbackClarificationContext)
        vm.setClarificationDraft("Explain the missing step.", for: context)
        vm.askClarification(for: context); await vm.waitForOperation()
        vm.tryAgain()
        XCTAssertFalse(vm.session!.canAskClarification(for: context))
        XCTAssertFalse(vm.session!.assistanceUsed)
        vm.setClarificationDraft("Cannot change an earlier discussion now.", for: context)
        vm.askClarification(for: context)
        XCTAssertEqual(tutor.calls, 1)
        XCTAssertEqual(vm.clarificationDraft(for: context), "")
        vm.openedClarifications(for: context)
        XCTAssertTrue(vm.session!.assistanceUsed)
        XCTAssertEqual(vm.session?.attempts, original.attempts)
    }

    func testFeedbackSourceChangeRejectsLateReplyAndKeepsDraftAndAssessment() async throws {
        let tutor = ClarificationTutor(); tutor.hold = true
        let original = assessed(delayed: true)
        let vm = model(original, tutor: tutor)
        let context = try XCTUnwrap(vm.session?.feedbackClarificationContext)
        vm.setClarificationDraft("Keep my feedback question.", for: context)
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
        XCTAssertEqual(vm.clarificationDraft(for: context), "Keep my feedback question.")
        XCTAssertEqual(vm.session?.attempts, original.attempts)
        XCTAssertEqual(vm.session?.delayedReview, original.delayedReview)
        XCTAssertFalse(vm.session!.assistanceUsed)
        XCTAssertNotNil(vm.clarificationErrorMessage)
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

    func testInspectingCurrentNotesAndSavedHelpDoesNotRewriteObsoleteSourceEvidence() throws {
        for delayed in [false, true] {
            let tutor = ClarificationTutor()
            var original = saved(phase: .exitCheck)
            if delayed { original.delayedReview = .init(previousSessionID: UUID(), scheduledFor: Date(), startedAt: Date(), round: 1) }
            let context = try XCTUnwrap(original.clarificationContext)
            original.clarifications = [.init(context: context, question: "A saved question", reply: tutor.reply,
                suppliedPageIndices: [0], previousExchangeIDs: [], providerID: "authored", modelID: nil)]
            let vm = model(original, tutor: tutor)
            vm.sourceIsCurrent = { _ in false }
            var writes = 0; vm.onChange = { _ in writes += 1 }
            vm.openedSource(); vm.openedClarifications(for: context)
            XCTAssertEqual(vm.session, original)
            XCTAssertEqual(writes, 0)
            // Valid current-source access retains the existing help policy.
            vm.sourceIsCurrent = { _ in true }
            vm.openedSource(); vm.openedClarifications(for: context)
            XCTAssertTrue(vm.session?.sourceOpened == true)
            XCTAssertTrue(vm.session?.clarificationHelpUsed == true)
            if delayed { XCTAssertTrue(vm.session?.delayedReview?.helpUsed == true) }
        }
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
    private func chapterFeedback(grade: LearningGrade = .partial, assisted: Bool = false,
                                 excluded: Bool = false, complete: Bool = false) throws -> LearningSession {
        let pdf = try LearningUIFixture.makePDF()
        let workspace = try LearningUIFixture.makeWorkspace(document: pdf, url: URL(fileURLWithPath: "/tmp/authored-chapter-feedback.pdf"))
        let map = try XCTUnwrap(workspace.learningStudyMap)
        let request = try XCTUnwrap(map.chapterRequest(for: XCTUnwrap(map.course?.modules.first)))
        var challenge = LearningUIFixture.challenge(request: request)
        let question = challenge.question
        challenge.question = .init(prompt: question.prompt, expectedAnswer: "PRIVATE CHAPTER KEY 112",
            hints: ["PRIVATE CHAPTER HINT 112"], kind: question.kind, gradingCriteria: question.gradingCriteria)
        var session = LearningSession(source: workspace.learningSessions[0].source, lesson: challenge.sessionEnvelope,
            phase: .exitCheck, providerID: "original-chapter-tutor", modelID: "original-model")
        session.chapter = .init(request: request, challenge: challenge)
        session.chapter?.position = "reasoning"; session.chapter?.scrollOffset = 317.25
        session.chapter?.assistanceUsed = assisted
        if assisted {
            session.chapter?.rescueDraft = "Retain my original prerequisite reasoning."
            session.chapter?.rescueFeedback = .init(grade: .correct, feedback: "Saved supported feedback.", nextStep: "Return to the argument.")
        }
        session.answerDraft = "My complete original chapter argument.\nClosedness keeps the subsequence limit in K."
        let assessment = LearningAssessment(grade: grade, feedback: "Explain how the limit belongs to the closed subset.",
            nextStep: "Connect the source hypothesis to this step.", criteria: question.gradingCriteria?.indices.map {
                .init(index: $0, outcome: grade == .correct ? .met : grade == .uncertain ? .uncertain : .notMet,
                      feedback: "Saved reasoning check \($0 + 1).")
            })
        var attempt = LearningAttempt(phase: .exitCheck, question: challenge.question, answer: session.answerDraft,
            assessment: assessment, assistanceUsed: assisted, providerID: session.providerID, modelID: session.modelID)
        if excluded { attempt.setAsideAt = Date(timeIntervalSince1970: 1_900_000_000) }
        session.attempts = [attempt]; session.feedback = assessment
        if complete { session.move(to: .complete) }
        return session
    }

    func testChapterFeedbackContextUsesOnlyExactAssessedArgumentAndSurvivesPersonalReview() throws {
        var session = try chapterFeedback()
        let attempt = try XCTUnwrap(session.latestExitAttempt)
        let context = try XCTUnwrap(session.feedbackClarificationContext)
        XCTAssertEqual(context.attemptID, attempt.id)
        for visible in [attempt.question.prompt, attempt.answer, attempt.assessment.feedback, attempt.assessment.nextStep]
            + (attempt.question.gradingCriteria ?? []) + (attempt.assessment.criteria?.map(\.feedback) ?? []) {
            XCTAssertTrue(context.content.contains(visible))
        }
        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(context), encoding: .utf8))
        XCTAssertFalse(encoded.contains("PRIVATE CHAPTER KEY 112"))
        XCTAssertFalse(encoded.contains("PRIVATE CHAPTER HINT 112"))
        XCTAssertFalse(context.content.contains(session.chapter!.challenge.refresher.check.expectedAnswer))
        XCTAssertTrue(session.canAskClarification(for: context))
        session.attempts[0].setAsideAt = Date()
        XCTAssertEqual(session.feedbackClarificationContext, context)
        session.move(to: .complete)
        XCTAssertEqual(session.feedbackClarificationContext, context)
        session.chapter?.rescueVisible = true
        XCTAssertNil(session.feedbackClarificationContext)
        XCTAssertFalse(session.canAskClarification(for: context))
        session.chapter?.rescueVisible = false
        session.move(to: .exitCheck)
        XCTAssertNil(session.feedbackClarificationContext)
        XCTAssertNil(session.clarificationContext) // No new question-help route is introduced.
        XCTAssertFalse(session.canAskClarification(for: context))
    }

    func testChapterFeedbackDiscussionPreservesEveryOriginalResultAndHelpState() async throws {
        for grade in [LearningGrade.correct, .partial, .incorrect, .uncertain] {
            for assisted in [false, true] {
                for excluded in [false, true] {
                    for complete in [false, true] {
                        let original = try chapterFeedback(grade: grade, assisted: assisted, excluded: excluded, complete: complete)
                        let tutor = ClarificationTutor()
                        tutor.reply = .init(answer: "Use the closedness hypothesis to justify the limit location.", basis: .suppliedNotes,
                            citations: [.init(pageIndex: 0, quote: LearningUIFixture.closedStatement)])
                        let vm = model(original, tutor: tutor)
                        let context = try XCTUnwrap(vm.session?.feedbackClarificationContext)
                        vm.setClarificationDraft("Why this criterion?", for: context)
                        vm.askClarification(for: context); await vm.waitForOperation()
                        vm.openedClarifications(for: context)
                        let result = try XCTUnwrap(vm.session)
                        XCTAssertEqual(tutor.calls, 1)
                        XCTAssertEqual(result.clarifications?.last?.context, context)
                        XCTAssertEqual(result.clarifications?.last?.question, "Why this criterion?")
                        XCTAssertTrue(result.clarificationDrafts?.isEmpty ?? true)
                        var normalized = result
                        normalized.clarifications = original.clarifications
                        normalized.clarificationDrafts = original.clarificationDrafts
                        normalized.updatedAt = original.updatedAt
                        XCTAssertEqual(normalized, original)
                        XCTAssertEqual(result.passedExitCheck, original.passedExitCheck)
                        XCTAssertEqual(result.assistanceUsed, original.assistanceUsed)
                    }
                }
            }
        }
    }

    func testLateChapterDiscussionCannotApplyAfterSourceChangeOrCancellation() async throws {
        for cancel in [false, true] {
            let original = try chapterFeedback(excluded: true)
            let tutor = ClarificationTutor(); tutor.hold = true
            tutor.reply = .init(answer: "Review the source hypothesis.", basis: .suppliedNotes,
                citations: [.init(pageIndex: 0, quote: LearningUIFixture.closedStatement)])
            let vm = model(original, tutor: tutor)
            let context = try XCTUnwrap(vm.session?.feedbackClarificationContext)
            vm.setClarificationDraft("Keep my unsent chapter question.", for: context)
            let before = vm.session
            vm.askClarification(for: context)
            for _ in 0..<1_000 where tutor.continuation == nil { await Task.yield() }
            let pending = try XCTUnwrap(tutor.continuation)
            // Capture completion while the operation is still live: cancel
            // clears the view model's task handle before the held reply returns.
            var completion: Task<Void, Never>?
            await withCheckedContinuation { (started: CheckedContinuation<Void, Never>) in
                completion = Task {
                    started.resume()
                    await vm.waitForOperation()
                }
            }
            let finished = try XCTUnwrap(completion)
            vm.setClarificationDraft("Do not replace a busy draft.", for: context)
            if cancel { vm.cancelClarification() } else { vm.sourceIsCurrent = { _ in false } }
            pending.resume(returning: tutor.reply); tutor.continuation = nil
            await finished.value
            XCTAssertEqual(vm.session, before)
            XCTAssertEqual(vm.clarificationDraft(for: context), "Keep my unsent chapter question.")
            XCTAssertFalse(vm.isBusy)
            if !cancel { XCTAssertNotNil(vm.clarificationErrorMessage) }
        }
    }

    func testChapterDiscussionAndFollowupPersistAndEarlierReplyRecordsHelpOnFreshArgument() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cauchy-ui-fixture-chapter-feedback-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = LearningUIFixtureController(rootPath: root.path)
        await controller.load()
        let document = try XCTUnwrap(controller.library?.selectedDocument)
        let map = try XCTUnwrap(document.studyMap.map)
        let request = try XCTUnwrap(map.chapterRequest(for: XCTUnwrap(map.course?.modules.first)))
        document.learning.startChapter(request: request, source: document.learning.sessions[0].source)
        await document.learning.waitForOperation()
        document.learning.answerDraft = "fixture correct"
        document.learning.submitAnswer(); await document.learning.waitForOperation(); document.learning.advance()
        let id = try XCTUnwrap(document.learning.selectedSessionID)
        let attempt = try XCTUnwrap(document.learning.session?.latestExitAttempt)
        document.learning.setAssessmentAside(true, sessionID: id, attemptID: attempt.id)
        let original = try XCTUnwrap(document.learning.session)
        let context = try XCTUnwrap(original.feedbackClarificationContext)
        document.learning.setClarificationDraft("Why was this chapter criterion met?", for: context)
        document.learning.askClarification(for: context); await document.learning.waitForOperation()
        document.learning.setClarificationDraft("Keep this chapter feedback follow-up.", for: context)
        let expected = document.learning.sessions.sorted { $0.id.uuidString < $1.id.uuidString }
        try await controller.flush()
        let restart = LearningUIFixtureController(rootPath: root.path)
        await restart.load()
        let restored = try XCTUnwrap(restart.library?.selectedDocument)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970; encoder.outputFormatting = [.sortedKeys]
        let originalAttempts = try encoder.encode(original.attempts)
        XCTAssertEqual(try encoder.encode(restored.learning.sessions.sorted { $0.id.uuidString < $1.id.uuidString }), try encoder.encode(expected))
        XCTAssertEqual(try encoder.encode(restored.studyMap.map), try encoder.encode(Optional(map)))
        restored.learning.select(id)
        XCTAssertEqual(restored.learning.session?.feedbackClarificationContext, context)
        XCTAssertEqual(restored.learning.clarificationDraft(for: context), "Keep this chapter feedback follow-up.")
        XCTAssertEqual(try encoder.encode(restored.learning.session!.attempts), originalAttempts)
        XCTAssertFalse(restored.learning.session!.assistanceUsed)
        restored.learning.freshChapterCheck(); await restored.learning.waitForOperation()
        XCTAssertFalse(restored.learning.session!.canAskClarification(for: context))
        restored.learning.answerDraft = "Keep my new chapter argument."
        let fresh = restored.learning.session
        restored.learning.setClarificationDraft("Cannot overwrite a historical follow-up.", for: context)
        restored.learning.askClarification(for: context)
        XCTAssertEqual(restored.learning.session, fresh)
        restored.learning.openedClarifications(for: context)
        XCTAssertTrue(restored.learning.session!.assistanceUsed)
        XCTAssertEqual(restored.learning.answerDraft, "Keep my new chapter argument.")
        XCTAssertEqual(try encoder.encode(restored.learning.session!.attempts), originalAttempts)
        XCTAssertEqual(restored.learning.clarificationDraft(for: context), "Keep this chapter feedback follow-up.")
        XCTAssertEqual(try encoder.encode(restored.studyMap.map), try encoder.encode(Optional(map)))
        try await restart.flush()
    }

    func testFeedbackDiscussionAndFollowupSurviveRealFixturePersistence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cauchy-ui-fixture-feedback-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = LearningUIFixtureController(rootPath: root.path)
        await controller.load()
        let document = try XCTUnwrap(controller.library?.selectedDocument)
        let original = try XCTUnwrap(document.learning.sessions.first { $0.phase == .complete })
        document.learning.select(original.id)
        let context = try XCTUnwrap(document.learning.session?.feedbackClarificationContext)
        document.learning.setClarificationDraft("What justified this assessment?", for: context)
        document.learning.askClarification(for: context); await document.learning.waitForOperation()
        document.learning.setClarificationDraft("A saved feedback follow-up", for: context)
        let expected = try XCTUnwrap(document.learning.session)
        try await controller.flush()
        let restart = LearningUIFixtureController(rootPath: root.path)
        await restart.load()
        let restored = try XCTUnwrap(restart.library?.selectedDocument)
        restored.learning.select(original.id)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970; encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try encoder.encode(restored.learning.session), try encoder.encode(expected))
        XCTAssertEqual(restored.learning.session?.feedbackClarificationContext, context)
        XCTAssertEqual(restored.learning.clarificationDraft(for: context), "A saved feedback follow-up")
        XCTAssertEqual(expected.attempts, original.attempts)
        XCTAssertEqual(expected.reviewDueAt, original.reviewDueAt)
        XCTAssertFalse(expected.assistanceUsed)
    }

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
