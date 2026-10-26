import XCTest
import PDFKit
@testable import Cauchy

@MainActor
private final class FailingStudyRunPlanner: LearningStudyPlannerProtocol {
    let providerID = "offline"
    let modelID: String? = "authored"
    let sourceLimit = 38_000
    func plan(source: LearningSource, corePages: [Int]) async throws -> LearningStudyPlanResponse { throw LearningError.invalidStudyMap }
    func course(units: [LearningStudyUnit]) async throws -> LearningCourse { throw LearningError.invalidCourse }
}

@MainActor
private final class UnavailableStudyRunTutor: LearningTutorProtocol {
    let providerID = "offline"
    let modelID: String? = "authored"
    func makeLesson(source: LearningSource) async throws -> LearningLesson { throw LearningError.invalidResponse }
    func assess(question: LearningQuestion, answer: String, source: LearningSource) async throws -> LearningAssessment { throw LearningError.invalidResponse }
    func newExitQuestion(lesson: LearningLesson, source: LearningSource, previous: [String]) async throws -> LearningQuestion { throw LearningError.invalidResponse }
}

@MainActor
final class LearningStudyRunTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let source = LearningSource(passages: [.init(pageIndex: 0,
        text: "A linear map preserves addition and scalar multiplication. Its kernel is the set of vectors mapped to zero.")])

    private func map() -> LearningStudyMap {
        let units = (0..<2).map { index in
            let id = UUID()
            return LearningStudyUnit(id: id, title: "Idea \(index + 1)", anchorPage: 0, sourceQuote: source.passages[0].text,
                pageIndices: [0], prerequisites: index == 0 ? [] : ["Idea 1"], proofRequired: true,
                proofQuote: source.passages[0].text, gaps: [], targets: LearningStudyKind.allCases.map {
                    .init(unitID: id, kind: $0, objective: "\($0.rawValue) requirement for idea \(index + 1)")
                })
        }
        let course = LearningCourse(title: "Authored course", overview: "Study in source order.",
            modules: [.init(title: "Chapter", goal: "Understand two ideas", unitIDs: units.map(\.id))], connections: [])
        return .init(pageSignatures: [LearningStudyInput.signature(source.passages[0].text)],
                     pages: [.init(pageIndex: 0, status: .mapped)], units: units, course: course)
    }

    private func session(target: LearningStudyTarget, itemID: UUID? = nil, grade: LearningGrade = .correct,
                         helped: Bool = false, delayed: Bool = false, date: Date? = nil) -> LearningSession {
        let criteria = ["Use the definition.", "Justify the inference.", "State the conclusion."]
        let question = LearningQuestion(prompt: "An authored question", expectedAnswer: "An authored justified answer.",
            hints: [], kind: target.kind, gradingCriteria: criteria)
        var lesson = LearningLesson(title: "Authored lesson", objective: target.objective, sourceQuote: source.passages[0].text,
            explanation: "An explanation", workedExample: "An example", diagnostic: question, practice: question, exitCheck: question)
        if target.kind == .proof {
            lesson.proof = .init(statement: "An authored statement", assumptions: ["An authored hypothesis"],
                strategy: "A complete argument", steps: (0..<12).map { .init(claim: "Claim \($0)", justification: "Reason \($0)") },
                conclusion: "The conclusion", sourceQuote: source.passages[0].text)
        }
        var saved = LearningSession(source: source, lesson: lesson, providerID: "offline", modelID: "authored")
        saved.studyTarget = target
        saved.studyRunItemID = itemID
        saved.phase = .complete
        var attempt = LearningAttempt(phase: .exitCheck, question: question, answer: "Authored reasoning",
            assessment: .init(grade: grade, feedback: "Authored feedback", nextStep: "Review if needed",
                criteria: criteria.indices.map { .init(index: $0, outcome: grade == .correct ? .met : .uncertain, feedback: "Authored criterion") }),
            assistanceUsed: helped, providerID: "offline", modelID: "authored")
        attempt.createdAt = date ?? now
        saved.attempts = [attempt]
        if delayed { saved.delayedReview = .init(previousSessionID: UUID(), scheduledFor: now, startedAt: now, round: 1) }
        return saved
    }

    private func replacingTargets(_ unit: LearningStudyUnit, with targets: [LearningStudyTarget]) -> LearningStudyUnit {
        .init(id: unit.id, title: unit.title, anchorPage: unit.anchorPage, sourceQuote: unit.sourceQuote,
            pageIndices: unit.pageIndices, prerequisites: unit.prerequisites, proofRequired: unit.proofRequired,
            proofQuote: unit.proofQuote, gaps: unit.gaps, targets: targets, reconciliation: unit.reconciliation,
            pendingSourceCorrection: unit.pendingSourceCorrection, sourceCorrectionIDs: unit.sourceCorrectionIDs)
    }

    private func recordedItem(for saved: LearningSession) throws -> LearningStudyRun.Item {
        let target = try XCTUnwrap(saved.studyTarget), attempt = try XCTUnwrap(saved.latestExitAttempt)
        var item = LearningStudyRun.Item(unitID: target.unitID, title: "Recorded requirement", target: target,
            mode: saved.delayedReview == nil ? .lesson : .delayedReview, existingSessionID: saved.id, earlierAttemptIDs: [])
        item.outcome = .init(sessionID: saved.id, attemptID: attempt.id, grade: attempt.assessment.grade,
            assistanceUsed: attempt.assistanceUsed, independentCorrect: attempt.hasIndependentCorrectResult, assessedAt: attempt.createdAt)
        return item
    }

    private func replacingAssessment(_ attempt: LearningAttempt, with assessment: LearningAssessment, helped: Bool? = nil) -> LearningAttempt {
        var replacement = LearningAttempt(phase: attempt.phase, question: attempt.question, answer: attempt.answer,
            assessment: assessment, assistanceUsed: helped ?? attempt.assistanceUsed, providerID: attempt.providerID, modelID: attempt.modelID)
        replacement.id = attempt.id; replacement.createdAt = attempt.createdAt; replacement.setAsideAt = attempt.setAsideAt
        return replacement
    }

    func testRecordedOutcomesRejectOptimisticRubricsAndCachedFlagsWithoutRewritingWork() throws {
        for target in map().units[0].targets {
            let original = session(target: target), item = try recordedItem(for: original)
            XCTAssertEqual(item.recordStatus(in: [original]), .verified)
            XCTAssertTrue(item.outcome?.independentCorrect == true)
            let attempt = try XCTUnwrap(original.latestExitAttempt)
            var incomplete = attempt.assessment
            // Keep the original optimistic outcome while its linked legacy assessment is inconsistent.
            let variants = [
                LearningAssessment(grade: .correct, feedback: incomplete.feedback, nextStep: incomplete.nextStep,
                    criteria: [.init(index: 0, outcome: .met, feedback: "One supplied criterion only.")]),
                LearningAssessment(grade: .correct, feedback: incomplete.feedback, nextStep: incomplete.nextStep,
                    criteria: attempt.assessment.criteria!.map { .init(index: $0.index, outcome: $0.index == 1 ? .notMet : .met, feedback: $0.feedback) }),
                LearningAssessment(grade: .correct, feedback: incomplete.feedback, nextStep: incomplete.nextStep,
                    criteria: attempt.assessment.criteria!.map { .init(index: $0.index, outcome: $0.index == 1 ? .uncertain : .met, feedback: $0.feedback) })
            ]
            for assessment in variants {
                var legacy = original; legacy.attempts[0] = replacingAssessment(attempt, with: assessment)
                let before = legacy
                XCTAssertFalse(legacy.attempts[0].hasIndependentCorrectResult)
                XCTAssertEqual(item.recordStatus(in: [legacy]), .assessmentNeedsChecking)
                XCTAssertEqual(legacy, before)
                XCTAssertEqual(item.outcome?.grade, .correct)
                XCTAssertTrue(item.outcome?.independentCorrect == true)
            }
            incomplete = .init(grade: .partial, feedback: attempt.assessment.feedback, nextStep: attempt.assessment.nextStep,
                criteria: attempt.assessment.criteria)
            var changed = original; changed.attempts[0] = replacingAssessment(attempt, with: incomplete)
            XCTAssertEqual(item.recordStatus(in: [changed]), .assessmentMismatch)
            changed = original; changed.attempts[0] = replacingAssessment(attempt, with: attempt.assessment, helped: true)
            XCTAssertEqual(item.recordStatus(in: [changed]), .assessmentMismatch)
            let assisted = session(target: target, helped: true)
            var impossible = try recordedItem(for: assisted)
            let captured = try XCTUnwrap(impossible.outcome)
            impossible.outcome = .init(sessionID: captured.sessionID, attemptID: captured.attemptID, grade: captured.grade,
                assistanceUsed: true, independentCorrect: true, assessedAt: captured.assessedAt)
            XCTAssertEqual(impossible.recordStatus(in: [assisted]), .assessmentNeedsChecking)
        }
    }

    func testRecordedOutcomeRequiresExactAssessmentRequirementAndActivity() throws {
        let target = map().units[0].targets[0]
        let saved = session(target: target), item = try recordedItem(for: saved)
        XCTAssertEqual(item.recordStatus(in: []), .assessmentUnavailable)
        var unattached = LearningStudyRun.Item(unitID: target.unitID, title: item.title, target: target,
            mode: .lesson, existingSessionID: nil, earlierAttemptIDs: [])
        unattached.outcome = item.outcome
        XCTAssertEqual(unattached.recordStatus(in: [saved]), .assessmentMismatch)
        var assigned = saved; assigned.studyRunItemID = unattached.id
        XCTAssertEqual(unattached.recordStatus(in: [assigned]), .verified)
        var priorWork = LearningStudyRun.Item(unitID: target.unitID, title: item.title, target: target,
            mode: .lesson, existingSessionID: saved.id, earlierAttemptIDs: [saved.attempts[0].id])
        priorWork.outcome = item.outcome
        XCTAssertEqual(priorWork.recordStatus(in: [saved]), .assessmentMismatch)
        var otherAttempt = saved; otherAttempt.attempts[0].id = UUID()
        XCTAssertEqual(item.recordStatus(in: [otherAttempt]), .assessmentUnavailable)
        var changes: [LearningStudyTarget] = []
        var revised = target; revised.revisionID = UUID(); changes.append(revised)
        changes += [.init(id: target.id, unitID: target.unitID, kind: target.kind, objective: "Earlier goal"),
            .init(id: target.id, unitID: UUID(), kind: target.kind, objective: target.objective),
            .init(id: target.id, unitID: target.unitID, kind: .application, objective: target.objective)]
        for changed in changes {
            var foreign = saved; foreign.studyTarget = changed
            XCTAssertEqual(item.recordStatus(in: [foreign]), .assessmentMismatch)
        }
        var unbound = saved; unbound.studyTarget = nil
        XCTAssertEqual(item.recordStatus(in: [unbound]), .assessmentMismatch)
        var delayed = saved; delayed.delayedReview = .init(previousSessionID: UUID(), scheduledFor: now, startedAt: now, round: 1)
        XCTAssertEqual(item.recordStatus(in: [delayed]), .assessmentMismatch)
        let delayedItem = try recordedItem(for: delayed)
        XCTAssertEqual(delayedItem.recordStatus(in: [delayed]), .verified)
        XCTAssertEqual(delayedItem.recordStatus(in: [saved]), .assessmentMismatch)
        var noOutcome = item; noOutcome.outcome = nil
        XCTAssertEqual(noOutcome.recordStatus(in: [saved]), .noNewCheck)
        var contextOnly = target; contextOnly.courseContext = "Reorganized course orientation."
        var reorganized = saved; reorganized.studyTarget = contextOnly
        XCTAssertEqual(item.recordStatus(in: [reorganized]), .verified)
        var draft = saved
        let attempt = saved.attempts[0]
        var wrongPhase = LearningAttempt(phase: .practice, question: attempt.question, answer: attempt.answer,
            assessment: attempt.assessment, assistanceUsed: false, providerID: attempt.providerID, modelID: attempt.modelID)
        wrongPhase.id = attempt.id; draft.attempts = [wrongPhase]
        XCTAssertEqual(item.recordStatus(in: [draft]), .assessmentMismatch)
        draft = saved; var wrongQuestion = attempt.question; wrongQuestion.kind = .application
        var wrongKind = LearningAttempt(phase: .exitCheck, question: wrongQuestion, answer: attempt.answer,
            assessment: attempt.assessment, assistanceUsed: false, providerID: attempt.providerID, modelID: attempt.modelID)
        wrongKind.id = attempt.id; draft.attempts = [wrongKind]
        XCTAssertEqual(item.recordStatus(in: [draft]), .assessmentMismatch)
        #if DEBUG
        let pdf = try LearningUIFixture.makePDF()
        let workspace = try LearningUIFixture.makeWorkspace(document: pdf, url: URL(fileURLWithPath: "/tmp/authored.pdf"))
        let fixtureMap = try XCTUnwrap(workspace.learningStudyMap)
        let module = try XCTUnwrap(fixtureMap.course?.modules.first)
        let request = try XCTUnwrap(fixtureMap.chapterRequest(for: module))
        var chapter = saved; chapter.chapter = .init(request: request, challenge: LearningUIFixture.challenge(request: request))
        XCTAssertEqual(item.recordStatus(in: [chapter]), .assessmentMismatch)
        #endif
    }

    func testRecordedOutcomeExclusionAndPersistenceRemainReadOnlyWithoutACourse() async throws {
        let target = map().units[0].targets[0]
        var saved = session(target: target)
        let item = try recordedItem(for: saved)
        saved.attempts[0].setAsideAt = now
        XCTAssertEqual(item.recordStatus(in: [saved]), .setAside)
        let originallyExcluded = try recordedItem(for: saved)
        XCTAssertFalse(originallyExcluded.outcome?.independentCorrect == true)
        saved.attempts[0].setAsideAt = nil
        XCTAssertEqual(item.recordStatus(in: [saved]), .verified)
        XCTAssertEqual(originallyExcluded.recordStatus(in: [saved]), .verified)
        XCTAssertFalse(originallyExcluded.outcome?.independentCorrect == true) // Reinstatement does not rewrite the old snapshot.
        var map = map(); map.course = nil
        var run = LearningStudyRun(pageSignatures: map.pageSignatures, items: [item], startedAt: now)
        run.state = .finished; run.endedAt = now; map.studyRuns = [run]
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cauchy-record-integrity-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = DocumentPersistenceService(root: root)
        let workspace = DocumentWorkspace(documentURL: root.appendingPathComponent("authored.pdf"), learningSessions: [saved], learningStudyMap: map)
        try await persistence.saveWorkspace(workspace, bookmarkData: nil)
        let file = persistence.workspaceDirectory(for: workspace.id).appendingPathComponent("learning.json")
        let bytes = try Data(contentsOf: file)
        let loaded = await persistence.loadWorkspace(id: workspace.id)
        let restored = try XCTUnwrap(loaded).workspace
        let restoredRun = try XCTUnwrap(restored.learningStudyMap?.studyRuns?.first)
        XCTAssertNil(restored.learningStudyMap?.course)
        XCTAssertEqual(restoredRun.items[0].recordStatus(in: restored.learningSessions), .verified)
        XCTAssertEqual(restoredRun.items[0].outcome, item.outcome)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertEqual(run.items[0], item)
    }

    func testPlanHasBoundedConceptProofApplicationOrderWithoutDuplicateUnits() throws {
        var map = map()
        // A chapter may refer to an earlier idea again; it is not another task.
        let course = try XCTUnwrap(map.course)
        map.course = .init(title: course.title, overview: course.overview,
            modules: course.modules + course.modules, connections: [])
        map.units[0] = replacingTargets(map.units[0], with: [map.units[0].targets[2], map.units[0].targets[0], map.units[0].targets[1]])
        let run = try XCTUnwrap(LearningStudyRun.plan(map: map, sessions: [], count: 100, now: now))
        XCTAssertEqual(run.items.count, 3)
        XCTAssertEqual(run.items.map(\.target.kind), [.concept, .proof, .application])
        XCTAssertEqual(Set(run.items.map { $0.target.id }).count, 3)
        XCTAssertEqual(run.attemptedCount, 0)
        XCTAssertEqual(run.state, .active)
        XCTAssertEqual(LearningStudyRun.plan(map: map, sessions: [], count: 2, now: now)?.items.count, 2)
    }

    func testRevisedRequirementKeepsEarlierWorkOutOfCreditReviewsAndPlans() throws {
        var map = map()
        let original = map.units[0].targets[0]
        let revised = LearningStudyTarget(id: original.id, unitID: original.unitID, kind: original.kind,
            objective: "Explain why preserving zero is necessary but insufficient for linearity.")
        map.units[0] = replacingTargets(map.units[0], with: [revised] + map.units[0].targets.dropFirst())
        var passed = session(target: original)
        passed.reviewDueAt = now.addingTimeInterval(-86_400)
        var reviewDraft = session(target: original, delayed: true)
        reviewDraft.phase = .exitCheck
        reviewDraft.attempts = []
        reviewDraft.answerDraft = "My earlier objective's unfinished review"
        let completedReview = session(target: original, delayed: true)
        let saved = [passed, reviewDraft, completedReview]

        XCTAssertNil(map.units[0].evidence(for: revised, sessions: saved))
        XCTAssertEqual(map.units[0].checkedTargetCount(sessions: saved), 0)
        XCTAssertNil(map.nextDelayedReview(sessions: [passed], now: now))
        XCTAssertNil(map.nextDelayedReview(sessions: saved, now: now))
        XCTAssertTrue(map.delayedEvidence(for: revised, sessions: saved).isEmpty)
        let next = try XCTUnwrap(map.nextStudy(sessions: saved))
        XCTAssertEqual(next.target, revised)
        XCTAssertNil(next.session)
        let planned = try XCTUnwrap(LearningStudyRun.plan(map: map, sessions: saved, count: 1, now: now))
        XCTAssertEqual(planned.items.first?.target, revised)
        XCTAssertEqual(planned.items.first?.mode, .lesson)
        XCTAssertNil(planned.items.first?.existingSessionID)
        // Earlier wording remains available for inspection under this requirement.
        XCTAssertEqual(Set(LearningRequirementHistory.sessions(for: revised, in: saved).map(\.id)), Set(saved.map(\.id)))
    }

    func testRequirementIdentityIncludesUnitKindAndObjectiveButNotCourseContext() throws {
        let map = map()
        let target = map.units[0].targets[0]
        var contextual = target
        contextual.courseContext = "A reorganized chapter with a revised course overview."
        XCTAssertTrue(target.matchesRequirement(contextual))
        XCTAssertFalse(target.matchesRequirement(nil))
        let different = [
            LearningStudyTarget(unitID: target.unitID, kind: target.kind, objective: target.objective),
            LearningStudyTarget(id: target.id, unitID: UUID(), kind: target.kind, objective: target.objective),
            LearningStudyTarget(id: target.id, unitID: target.unitID, kind: .proof, objective: target.objective),
            LearningStudyTarget(id: target.id, unitID: target.unitID, kind: target.kind, objective: target.objective + " Revised.")
        ]
        for other in different {
            XCTAssertFalse(target.matchesRequirement(other))
            var saved = session(target: other)
            let attempt = saved.attempts[0]
            var question = attempt.question
            question.kind = target.kind // A raw matching question kind is insufficient.
            saved.attempts = [.init(phase: attempt.phase, question: question, answer: attempt.answer,
                assessment: attempt.assessment, assistanceUsed: attempt.assistanceUsed,
                providerID: attempt.providerID, modelID: attempt.modelID)]
            XCTAssertNil(map.units[0].evidence(for: target, sessions: [saved]))
            let item = LearningStudyRun.Item(unitID: target.unitID, title: "Pinned requirement", target: target,
                mode: .lesson, existingSessionID: saved.id, earlierAttemptIDs: [])
            XCTAssertNil(item.session(in: [saved]))
            saved.studyRunItemID = item.id
            XCTAssertNil(item.session(in: [saved]))
        }
        var saved = session(target: contextual)
        saved.reviewDueAt = now
        XCTAssertEqual(map.units[0].evidence(for: target, sessions: [saved]), saved.latestExitAttempt)
        XCTAssertEqual(map.nextDelayedReview(sessions: [saved], now: now)?.previous.id, saved.id)
        var draft = saved
        draft.phase = .practice; draft.attempts = []
        let run = try XCTUnwrap(LearningStudyRun.plan(map: map, sessions: [draft], count: 1, now: now))
        XCTAssertEqual(run.items[0].existingSessionID, draft.id)
        XCTAssertEqual(run.items[0].session(in: [draft]), draft)
        XCTAssertNil(run.blocker(in: map, sessions: [draft]))
        let vm = LearningStudyMapViewModel(map: map)
        try vm.startStudyRun(run)
    }

    func testRevisedRequirementsStartSeparateLessonsAndPreserveHistoricalWorkAcrossRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cauchy-ui-fixture-requirement-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let seed = LearningUIFixtureController(rootPath: root.path)
        await seed.load()
        let originalDocument = try XCTUnwrap(seed.library?.selectedDocument)
        let originalMap = try XCTUnwrap(originalDocument.studyMap.map)
        let due = try XCTUnwrap(originalMap.nextDelayedReview(sessions: originalDocument.learning.sessions, now: Date()))
        originalDocument.learning.startDelayedReview(due)
        await originalDocument.learning.waitForOperation()
        originalDocument.learning.answerDraft = "Earlier objective's unsubmitted delayed argument."
        let oldDraftID = try XCTUnwrap(originalDocument.learning.session?.id)
        try await seed.flush()
        var workspace = originalDocument.snapshot
        var revisedMap = originalMap
        let previousConcept = revisedMap.units[0].targets[0]
        let revisedConcept = LearningStudyTarget(id: previousConcept.id, unitID: previousConcept.unitID, kind: previousConcept.kind,
            objective: "Explain where closedness is needed to keep the subsequence limit in the subset.")
        let revisedApplication = LearningStudyTarget(id: due.target.id, unitID: due.target.unitID, kind: due.target.kind,
            objective: "Use the continuous image result with a restricted closed domain.")
        revisedMap.units[0] = replacingTargets(revisedMap.units[0], with: revisedMap.units[0].targets.map {
            $0.id == revisedConcept.id ? revisedConcept : $0
        })
        revisedMap.units[1] = replacingTargets(revisedMap.units[1], with: revisedMap.units[1].targets.map {
            $0.id == revisedApplication.id ? revisedApplication : $0
        })
        revisedMap.updatedAt = Date()
        workspace.learningStudyMap = revisedMap
        let persistence = DocumentPersistenceService(root: root.appendingPathComponent("workspaces"))
        try await persistence.saveWorkspace(workspace, bookmarkData: nil)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970; encoder.outputFormatting = [.sortedKeys]
        let oldWork = try encoder.encode(workspace.learningSessions)

        let current = LearningUIFixtureController(rootPath: root.path)
        await current.load()
        let document = try XCTUnwrap(current.library?.selectedDocument)
        let map = try XCTUnwrap(document.studyMap.map)
        XCTAssertNil(map.nextDelayedReview(sessions: document.learning.sessions, now: Date()))
        XCTAssertEqual(map.units[1].checkedTargetCount(sessions: document.learning.sessions), 0)
        XCTAssertEqual(map.nextStudy(sessions: document.learning.sessions)?.target, revisedConcept)
        XCTAssertNil(map.nextStudy(sessions: document.learning.sessions)?.session)
        let history = LearningRequirementHistory.entries(for: revisedApplication, in: document.learning.sessions)
        XCTAssertTrue(history.contains { $0.requirementObjective == due.target.objective && !$0.isDraft })
        XCTAssertTrue(history.contains { $0.sessionID == oldDraftID && $0.isDraft })
        document.learning.select(due.previous.id)
        XCTAssertEqual(try encoder.encode(document.learning.sessions), oldWork)
        document.study(previousConcept, unit: originalMap.units[0])
        XCTAssertFalse(document.learning.isBusy)
        XCTAssertEqual(document.learning.selectedSessionID, due.previous.id)

        // Stale recommendations cannot relabel old evidence or resume an old draft as the new objective.
        for activeID in [UUID?.none, oldDraftID] {
            let previous = try XCTUnwrap(document.learning.sessions.first { $0.id == (activeID ?? due.previous.id) })
            document.learning.startDelayedReview(.init(unit: map.units[1], target: revisedApplication,
                previous: previous, dueAt: due.dueAt, activeSessionID: activeID))
            XCTAssertFalse(document.learning.isBusy)
            XCTAssertEqual(document.learning.selectedSessionID, due.previous.id)
            XCTAssertEqual(try encoder.encode(document.learning.sessions), oldWork)
        }

        document.study(revisedConcept, unit: map.units[0])
        await document.learning.waitForOperation()
        XCTAssertNil(document.learning.errorMessage)
        let newID = try XCTUnwrap(document.learning.session?.id)
        XCTAssertTrue(revisedConcept.matchesRequirement(document.learning.session?.studyTarget))
        XCTAssertEqual(document.learning.session?.lesson.objective, revisedConcept.objective)
        XCTAssertEqual(document.learning.session?.phase, .diagnostic)
        XCTAssertEqual(document.learning.sessions.count, workspace.learningSessions.count + 1)
        XCTAssertEqual(try encoder.encode(document.learning.sessions.filter { $0.id != newID }), oldWork)
        document.study(revisedConcept, unit: map.units[0])
        XCTAssertEqual(document.learning.selectedSessionID, newID)
        XCTAssertFalse(document.learning.isBusy)
        document.learning.answerDraft = "New objective, separate saved reasoning."
        try await current.flush()

        let restarted = LearningUIFixtureController(rootPath: root.path)
        await restarted.load()
        let restored = try XCTUnwrap(restarted.library?.selectedDocument)
        let restoredMap = try XCTUnwrap(restored.studyMap.map)
        XCTAssertEqual(try encoder.encode(restoredMap), try encoder.encode(map))
        XCTAssertEqual(try encoder.encode(restored.learning.sessions.filter { $0.id != newID }), oldWork)
        restored.study(revisedConcept, unit: restoredMap.units[0])
        XCTAssertEqual(restored.learning.selectedSessionID, newID)
        XCTAssertEqual(restored.learning.answerDraft, "New objective, separate saved reasoning.")
        XCTAssertFalse(restored.learning.isBusy)
        XCTAssertEqual(restoredMap.nextStudy(sessions: restored.learning.sessions)?.session?.id, newID)
        XCTAssertNil(restoredMap.nextDelayedReview(sessions: restored.learning.sessions, now: Date()))
        XCTAssertEqual(LearningRequirementHistory.entries(for: revisedApplication, in: restored.learning.sessions), history)
    }

    func testDueReviewLeadsAndKeepsItsOwnEvidenceKindAndSession() throws {
        let map = map()
        let target = map.units[1].targets[2]
        var original = session(target: target, date: now.addingTimeInterval(-2 * 86_400))
        original.reviewDueAt = now.addingTimeInterval(-86_400)
        let run = try XCTUnwrap(LearningStudyRun.plan(map: map, sessions: [original], now: now))
        XCTAssertEqual(run.items.first?.mode, .delayedReview)
        XCTAssertEqual(run.items.first?.target.id, target.id)
        XCTAssertEqual(run.items.first?.target.kind, .application)
        XCTAssertNil(run.items.first?.existingSessionID)
        XCTAssertEqual(run.items[1].mode, .lesson)
        XCTAssertEqual(run.items[1].target.kind, .concept)
        XCTAssertEqual(run.items.count, 3)
    }

    func testPinnedDelayedTargetDoesNotOpenAnUnrelatedEarlierDueCheck() throws {
        let map = map()
        let targets = [map.units[0].targets[0], map.units[1].targets[2]]
        var originals = targets.map { session(target: $0, date: now.addingTimeInterval(-3 * 86_400)) }
        originals[0].reviewDueAt = now.addingTimeInterval(-2 * 86_400)
        originals[1].reviewDueAt = now.addingTimeInterval(-86_400)
        XCTAssertEqual(map.nextDelayedReview(sessions: originals, now: now)?.target.id, targets[0].id)
        XCTAssertEqual(map.nextDelayedReview(sessions: originals, now: now, targetID: targets[1].id)?.target.id, targets[1].id)
        XCTAssertNil(map.nextDelayedReview(sessions: originals, now: now, targetID: UUID()))
    }

    func testReviewOnlyPlanOrdersSavedDraftBeforeDueChecksAndKeepsKindsDistinct() throws {
        let map = map()
        let targets = map.units[0].targets
        var originals = targets.map { session(target: $0, date: now.addingTimeInterval(-4 * 86_400)) }
        for index in originals.indices {
            originals[index].reviewDueAt = now.addingTimeInterval(TimeInterval(index - 3) * 86_400)
        }
        var draft = session(target: targets[2], delayed: true)
        draft.phase = .exitCheck
        draft.attempts = []
        draft.answerDraft = "My unfinished application argument"
        let sessions = originals + [draft]
        let run = try XCTUnwrap(LearningStudyRun.plan(map: map, sessions: sessions, count: 100, focus: .reviewOnly, now: now))
        XCTAssertEqual(run.items.map(\.target.id), [targets[2].id, targets[0].id, targets[1].id])
        XCTAssertEqual(run.items.map(\.target.kind), [.application, .concept, .proof])
        XCTAssertTrue(run.items.allSatisfy { $0.mode == .delayedReview })
        XCTAssertEqual(run.items[0].session(in: sessions), draft)
        XCTAssertEqual(run.items[0].existingSessionID, draft.id)
        XCTAssertEqual(LearningStudyRun.plan(map: map, sessions: sessions, count: 2, focus: .reviewOnly, now: now)?.items.count, 2)
        let restored = try JSONDecoder().decode(LearningStudyRun.self, from: JSONEncoder().encode(run))
        XCTAssertEqual(restored, run)
        XCTAssertEqual(restored.currentItem?.session(in: sessions)?.answerDraft, draft.answerDraft)
    }

    func testReviewOnlyPlanDoesNotFillWithNewOrFutureOrBlockedRequirements() throws {
        var map = map()
        var due = session(target: map.units[0].targets[0])
        due.reviewDueAt = now
        var future = session(target: map.units[0].targets[1])
        future.reviewDueAt = now.addingTimeInterval(1)
        var blocked = session(target: map.units[1].targets[0])
        blocked.reviewDueAt = now.addingTimeInterval(-86_400)
        map.units[1].pendingSourceCorrection = true
        let sessions = [due, future, blocked]
        let run = try XCTUnwrap(LearningStudyRun.plan(map: map, sessions: sessions, focus: .reviewOnly, now: now))
        XCTAssertEqual(run.items.map(\.target.id), [due.studyTarget!.id])
        XCTAssertNil(LearningStudyRun.plan(map: map, sessions: [future, blocked], focus: .reviewOnly, now: now))
        XCTAssertNil(LearningStudyRun.plan(map: map, sessions: [], focus: .reviewOnly, now: now))
        XCTAssertNotNil(LearningStudyRun.plan(map: map, sessions: [], now: now))
        let mixed = try XCTUnwrap(LearningStudyRun.plan(map: map, sessions: sessions, now: now))
        XCTAssertEqual(mixed.items.filter { $0.mode == .delayedReview }.count, 1)
        XCTAssertTrue(mixed.items.contains { $0.mode == .lesson })
    }

    func testReviewOnlyKeepsSavedSourceBlockerActionable() throws {
        var map = map()
        var draft = session(target: map.units[0].targets[0], delayed: true)
        draft.phase = .exitCheck; draft.attempts = []; draft.answerDraft = "Keep this draft"
        map.units[0].pendingSourceCorrection = true
        let run = try XCTUnwrap(LearningStudyRun.plan(map: map, sessions: [draft], focus: .reviewOnly, now: now))
        XCTAssertEqual(run.blocker(in: map, sessions: [draft]),
                       .sourceReview(unitID: map.units[0].id, title: map.units[0].title, pageIndex: 0))
        XCTAssertEqual(run.currentItem?.session(in: [draft]), draft)
    }

    func testBlockedSourceRemainsFirstAndCannotBeSkippedByThePlan() throws {
        var map = map()
        let unit = map.units[0]
        map.units[0] = .init(id: unit.id, title: unit.title, anchorPage: 0, sourceQuote: unit.sourceQuote,
            pageIndices: [0], prerequisites: [], proofRequired: true, proofQuote: nil,
            gaps: ["The required proof is omitted."], targets: [unit.targets[0], unit.targets[2]])
        let run = try XCTUnwrap(LearningStudyRun.plan(map: map, sessions: [], now: now))
        XCTAssertEqual(run.items.count, 1)
        XCTAssertEqual(run.items[0].unitID, unit.id)
        XCTAssertEqual(run.blocker(in: map, sessions: []), .sourceReview(unitID: unit.id, title: unit.title, pageIndex: 0))
    }

    func testAdvanceReferencesARealCompletedIndependentAttemptWithoutChangingIt() throws {
        let map = map()
        var run = try XCTUnwrap(LearningStudyRun.plan(map: map, sessions: [], now: now))
        let item = run.items[0]
        let completed = session(target: item.target, itemID: item.id)
        let before = completed
        XCTAssertTrue(run.advance(map: map, sessions: [completed], at: now))
        XCTAssertEqual(run.currentIndex, 1)
        XCTAssertEqual(run.items[0].outcome?.attemptID, completed.attempts[0].id)
        XCTAssertEqual(run.items[0].outcome?.sessionID, completed.id)
        XCTAssertTrue(run.items[0].outcome?.independentCorrect == true)
        XCTAssertEqual(completed, before)
        XCTAssertEqual(map.units[0].checkedTargetCount(sessions: [completed]), 1)
    }

    func testUncertainIncorrectAndHelpedAnswersStopProgressAndRemainTruthfulOnFinish() throws {
        let map = map()
        for (grade, helped) in [(LearningGrade.uncertain, false), (.incorrect, false), (.partial, false), (.correct, true)] {
            var run = try XCTUnwrap(LearningStudyRun.plan(map: map, sessions: [], now: now))
            let item = run.items[0]
            let completed = session(target: item.target, itemID: item.id, grade: grade, helped: helped)
            XCTAssertFalse(run.advance(map: map, sessions: [completed], at: now))
            XCTAssertEqual(run.currentIndex, 0)
            run.finish(sessions: [completed], at: now)
            XCTAssertEqual(run.state, .finished)
            XCTAssertEqual(run.attemptedCount, 1)
            XCTAssertEqual(run.items[0].outcome?.grade, grade)
            XCTAssertEqual(run.items[0].outcome?.assistanceUsed, helped)
            XCTAssertFalse(run.items[0].outcome!.independentCorrect)
            XCTAssertEqual(map.units[0].checkedTargetCount(sessions: [completed]), 0)
            XCTAssertNil(run.items[1].outcome)
        }
    }

    func testExistingExitEvidenceIsNotWorkInThisRunAndAnotherLessonCannotAttachIt() throws {
        let map = map()
        let old = session(target: map.units[0].targets[0], grade: .partial)
        var run = try XCTUnwrap(LearningStudyRun.plan(map: map, sessions: [old], now: now))
        XCTAssertEqual(run.items[0].existingSessionID, old.id)
        XCTAssertNil(run.items[0].newExitAttempt(in: [old]))
        let unrelated = session(target: map.units[0].targets[0])
        XCTAssertNil(run.items[0].session(in: [unrelated]))
        run.finish(sessions: [old, unrelated], at: now)
        XCTAssertEqual(run.attemptedCount, 0)
        XCTAssertEqual(run.state, .finished)
    }

    func testNewAssignedLessonTakesPrecedenceOverTheEarlierSavedLesson() throws {
        let map = map()
        var old = session(target: map.units[0].targets[0], grade: .partial)
        old.updatedAt = now.addingTimeInterval(10_000)
        let run = try XCTUnwrap(LearningStudyRun.plan(map: map, sessions: [old], now: now))
        let item = run.items[0]
        let revised = session(target: item.target, itemID: item.id)
        XCTAssertEqual(item.session(in: [old, revised])?.id, revised.id)
        XCTAssertEqual(item.newExitAttempt(in: [old, revised])?.1.id, revised.latestExitAttempt?.id)
    }

    func testAChangedLatestQuestionCannotFallBackToAnEarlierSuccessfulCheck() throws {
        let map = map()
        let run = try XCTUnwrap(LearningStudyRun.plan(map: map, sessions: [], now: now))
        let item = run.items[0]
        var completed = session(target: item.target, itemID: item.id)
        let wrongKind = session(target: map.units[0].targets[1])
        completed.attempts += wrongKind.attempts
        XCTAssertNil(item.newExitAttempt(in: [completed]))
    }

    func testLaterRequirementCannotSkipEarlierOpenWorkOrNewlyMissingProof() throws {
        var map = map()
        var run = try XCTUnwrap(LearningStudyRun.plan(map: map, sessions: [], now: now))
        // Even if a later result is imported, an earlier obligation remains.
        run.items = [run.items[2]]
        let later = session(target: run.items[0].target, itemID: run.items[0].id)
        XCTAssertEqual(run.blocker(in: map, sessions: [later]),
            .earlierRequirement(unitID: map.units[0].id, target: map.units[0].targets[0], title: map.units[0].title))
        XCTAssertFalse(run.advance(map: map, sessions: [later], at: now))
        map.units[0].pendingSourceCorrection = true
        XCTAssertEqual(run.blocker(in: map, sessions: [later]),
            .sourceReview(unitID: map.units[0].id, title: map.units[0].title, pageIndex: 0))
    }

    func testPauseResumeAndEarlyFinishNeverCreateAttemptsOrCompleteUnfinishedMaterial() throws {
        let map = map()
        var run = try XCTUnwrap(LearningStudyRun.plan(map: map, sessions: [], now: now))
        run.items = [run.items[1]]
        var saved = session(target: run.items[0].target, itemID: run.items[0].id)
        saved.attempts = []; saved.phase = .practice; saved.answerDraft = "Unsent proof reasoning."
        saved.lessonPartIndex = 5
        let before = saved
        run.pause(at: now)
        XCTAssertEqual(run.state, .paused)
        XCTAssertFalse(run.advance(map: map, sessions: [saved], at: now))
        let restored = try JSONDecoder().decode(LearningStudyRun.self, from: JSONEncoder().encode(run))
        XCTAssertEqual(restored.currentItem?.session(in: [saved]), saved)
        run = restored; run.resume()
        XCTAssertEqual(run.state, .active)
        run.finish(sessions: [saved], at: now)
        XCTAssertEqual(run.attemptedCount, 0)
        XCTAssertTrue(run.items.allSatisfy { $0.outcome == nil })
        XCTAssertEqual(saved, before)
        XCTAssertEqual(saved.lesson.proof?.steps.count, 12)
        XCTAssertEqual(saved.currentLessonPartIndex, 5)
        XCTAssertEqual(map.units[0].checkedTargetCount(sessions: [saved]), 0)
    }

    func testChangedSourceOrRequirementStopsTheSavedPlan() throws {
        let original = map()
        let run = try XCTUnwrap(LearningStudyRun.plan(map: original, sessions: [], now: now))
        var changed = original
        let target = changed.units[0].targets[0]
        var targets = changed.units[0].targets
        targets[0] = .init(id: target.id, unitID: target.unitID, kind: target.kind, objective: "A different requirement")
        changed.units[0] = replacingTargets(changed.units[0], with: targets)
        XCTAssertEqual(run.blocker(in: changed, sessions: []), .changedRequirement)
        var differentSource = original
        differentSource = .init(pageSignatures: ["changed"], pages: differentSource.pages, units: differentSource.units, course: differentSource.course)
        XCTAssertEqual(run.blocker(in: differentSource, sessions: []), .changedSource)
    }

    func testOnlyOneRunIsActiveAndHistoryAndLegacyMapDecodingSurvive() throws {
        let map = map()
        let run = try XCTUnwrap(LearningStudyRun.plan(map: map, sessions: [], now: now))
        let vm = LearningStudyMapViewModel(map: map)
        var writes = 0
        vm.onChange = { _ in writes += 1 }
        try vm.startStudyRun(run)
        XCTAssertThrowsError(try vm.startStudyRun(run))
        vm.updateStudyRun(run.id) { $0.pause(at: now) }
        XCTAssertEqual(vm.currentStudyRun?.state, .paused)
        vm.updateStudyRun(UUID()) { $0.finish(sessions: [], at: now) }
        XCTAssertEqual(vm.currentStudyRun?.state, .paused)
        vm.updateStudyRun(run.id) { $0.finish(sessions: [], at: now) }
        let next = try XCTUnwrap(LearningStudyRun.plan(map: map, sessions: [], now: now))
        try vm.startStudyRun(next)
        XCTAssertEqual(vm.map?.studyRuns?.count, 2)
        XCTAssertEqual(writes, 4)
        let encoded = try JSONEncoder().encode(vm.map!)
        XCTAssertEqual(try JSONDecoder().decode(LearningStudyMap.self, from: encoded).studyRuns?.count, 2)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json.removeValue(forKey: "studyRuns")
        let legacy = try JSONDecoder().decode(LearningStudyMap.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(legacy.studyRuns)
    }

#if DEBUG
    func testSavedEarlierRequirementOpensLocallyWithoutChangingActiveOrPausedPlans() async throws {
        for paused in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("cauchy-ui-fixture-offline-earlier-\(UUID())")
            defer { try? FileManager.default.removeItem(at: root) }
            let pdf = try LearningUIFixture.makePDF()
            var workspace = try LearningUIFixture.makeWorkspace(document: pdf, url: root.appendingPathComponent("authored.pdf"))
            var map = try XCTUnwrap(workspace.learningStudyMap)
            let unit = map.units[0]
            var earlier = try XCTUnwrap(workspace.learningSessions.first { $0.studyTarget?.unitID == unit.id })
            earlier.answerDraft = "Keep this saved prerequisite reasoning exactly."
            let target = unit.targets[1]
            var current = LearningSession(source: earlier.source, lesson: LearningUIFixture.lesson(source: earlier.source, target: target),
                providerID: "authored-offline-fixture", modelID: "deterministic-v1")
            current.studyTarget = target
            current.answerDraft = "Keep the later proof draft while reviewing its prerequisite."
            var run = LearningStudyRun(pageSignatures: map.pageSignatures, items: [
                .init(unitID: unit.id, title: unit.title, target: target, mode: .lesson,
                    existingSessionID: current.id, earlierAttemptIDs: [])
            ], startedAt: now)
            if paused { run.pause(at: now) }
            map.studyRuns = [run]
            workspace.learningStudyMap = map
            workspace.learningSessions = [current, earlier]
            let persistence = DocumentPersistenceService(root: root)
            try await persistence.saveWorkspace(workspace, bookmarkData: nil)
            let file = persistence.workspaceDirectory(for: workspace.id).appendingPathComponent("learning.json")
            let originalBytes = try Data(contentsOf: file)
            let loaded = await persistence.loadWorkspace(id: workspace.id)
            let restored = try XCTUnwrap(loaded).workspace
            var tutorRequests = 0
            let learning = LearningViewModel(makeTutor: { tutorRequests += 1; return UnavailableStudyRunTutor() })
            let document = LearningDocument(workspace: restored, document: pdf, bookmarkData: nil, learning: learning)
            learning.select(current.id)
            var learningWrites = 0, mapWrites = 0
            learning.onChange = { _ in learningWrites += 1 }
            document.studyMap.onChange = { _ in mapWrites += 1 }
            XCTAssertNil(document.studyRunRecovery(for: run))
            let blocker = try XCTUnwrap(run.blocker(in: map, sessions: learning.sessions))
            guard case .earlierRequirement(_, let prerequisite, _) = blocker else { return XCTFail("Expected the earlier concept requirement") }
            // The card requires an assistant only if this exact local lookup is empty.
            XCTAssertEqual(prerequisite.savedLesson(in: learning.sessions)?.id, earlier.id)
            document.continueStudyRun()
            await learning.waitForOperation()
            XCTAssertEqual(learning.selectedSessionID, earlier.id)
            XCTAssertEqual(learning.answerDraft, earlier.answerDraft)
            XCTAssertNil(learning.errorMessage)
            XCTAssertEqual(tutorRequests, 0)
            XCTAssertEqual(learningWrites, 0)
            XCTAssertEqual(mapWrites, 0)
            XCTAssertEqual(learning.sessions, restored.learningSessions)
            XCTAssertEqual(document.studyMap.map, restored.learningStudyMap)
            XCTAssertEqual(document.studyMap.currentStudyRun, run)
            XCTAssertEqual(try Data(contentsOf: file), originalBytes)
        }
    }

    func testSavedLessonLookupRejectsOtherVersionsKindsUnitsAndReviewActivities() throws {
        let pdf = try LearningUIFixture.makePDF()
        let workspace = try LearningUIFixture.makeWorkspace(document: pdf, url: URL(fileURLWithPath: "/tmp/authored.pdf"))
        let map = try XCTUnwrap(workspace.learningStudyMap)
        let ordinary = try XCTUnwrap(workspace.learningSessions.first { $0.phase == .practice })
        let target = try XCTUnwrap(ordinary.studyTarget)
        var targets: [LearningStudyTarget] = []
        var changed = target; changed.revisionID = UUID(); targets.append(changed)
        targets.append(.init(id: target.id, unitID: target.unitID, kind: target.kind, objective: "Earlier wording"))
        targets.append(.init(id: target.id, unitID: target.unitID, kind: .application, objective: target.objective))
        targets.append(.init(id: target.id, unitID: UUID(), kind: target.kind, objective: target.objective))
        targets.append(.init(unitID: target.unitID, kind: target.kind, objective: target.objective))
        var noise = targets.map { other in var saved = ordinary; saved.id = UUID(); saved.studyTarget = other; return saved }
        var delayed = ordinary; delayed.id = UUID()
        delayed.delayedReview = .init(previousSessionID: UUID(), scheduledFor: now, startedAt: now, round: 1)
        let request = try XCTUnwrap(map.course?.modules.first.flatMap { map.chapterRequest(for: $0) })
        var chapter = ordinary; chapter.id = UUID(); chapter.chapter = .init(request: request, challenge: LearningUIFixture.challenge(request: request))
        var unbound = ordinary; unbound.id = UUID(); unbound.studyTarget = nil
        noise += [delayed, chapter, unbound]
        XCTAssertNil(target.savedLesson(in: noise)) // Missing teaching must still require an assistant.
        var contextOnly = ordinary
        var contextual = target; contextual.courseContext = "Reorganized orientation only."
        contextOnly.studyTarget = contextual
        XCTAssertEqual(target.savedLesson(in: noise + [contextOnly])?.id, ordinary.id)
        XCTAssertEqual(target.savedLesson(in: [ordinary] + noise), ordinary)
    }

    func testChangedTranscriptionRecoveryPreservesActiveAndPausedPlansAcrossRestart() async throws {
        for paused in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("cauchy-ui-fixture-run-recovery-\(UUID())")
            defer { try? FileManager.default.removeItem(at: root) }
            let controller = LearningUIFixtureController(rootPath: root.path)
            await controller.load()
            let document = try XCTUnwrap(controller.library?.selectedDocument)
            let run = try XCTUnwrap(LearningStudyRun.plan(map: try XCTUnwrap(document.studyMap.map),
                sessions: document.learning.sessions, count: 2, now: Date()))
            document.beginStudyRun(run)
            await document.learning.waitForOperation()
            document.learning.answerDraft = "Keep this delayed argument and all earlier evidence."
            let saved = try XCTUnwrap(document.learning.session)
            if paused { document.pauseStudyRun() }
            let text = try XCTUnwrap(document.pdfDocument.page(at: 0)?.string)
            try document.studyMap.saveCorrection(pageIndex: 0, originalText: text,
                correctedText: text + "\nAuthored verified amendment.", note: "Compared with original PDF", confirmed: true)
            let beforeMap = document.studyMap.map
            let beforeSessions = document.learning.sessions
            let recovery = try XCTUnwrap(document.studyRunRecovery(for: try XCTUnwrap(document.studyMap.currentStudyRun)))
            XCTAssertEqual(recovery.pageIndex, 0)
            XCTAssertEqual(recovery.savedSessionID, saved.id)
            XCTAssertEqual(recovery.blocker, .changedSource)
            document.learning.showSections()
            document.continueStudyRun()
            XCTAssertTrue(document.notesVisible)
            XCTAssertEqual(document.notesPageIndex, 0)
            document.inspectStudyRunWork()
            XCTAssertEqual(document.learning.selectedSessionID, saved.id)
            XCTAssertFalse(document.canAdvanceStudyRun)
            XCTAssertFalse(document.advanceStudyRun())
            XCTAssertFalse(document.learning.isBusy)
            XCTAssertEqual(document.learning.sessions, beforeSessions)
            XCTAssertEqual(document.studyMap.map, beforeMap)
            try await controller.flush()

            let restarted = LearningUIFixtureController(rootPath: root.path)
            await restarted.load()
            let restored = try XCTUnwrap(restarted.library?.selectedDocument)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970; encoder.outputFormatting = [.sortedKeys]
            restored.continueStudyRun()
            restored.inspectStudyRunWork()
            XCTAssertEqual(restored.learning.selectedSessionID, saved.id)
            XCTAssertEqual(try encoder.encode(restored.learning.sessions), try encoder.encode(beforeSessions))
            XCTAssertEqual(try encoder.encode(restored.studyMap.map), try encoder.encode(beforeMap))
            restored.finishStudyRun()
            XCTAssertEqual(restored.studyMap.currentStudyRun?.state, .finished)
            XCTAssertEqual(restored.studyMap.currentStudyRun?.attemptedCount, 0)
            XCTAssertTrue(restored.studyMap.currentStudyRun?.items.allSatisfy { $0.outcome == nil } == true)
            XCTAssertEqual(try encoder.encode(restored.learning.sessions), try encoder.encode(beforeSessions))
        }
    }

    func testPlanRecoveryFindsChangedPDFBeforeInventoryRebuildAndBoundsRemovedPages() async throws {
        for removePage in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("cauchy-ui-fixture-run-pdf-recovery-\(UUID())")
            defer { try? FileManager.default.removeItem(at: root) }
            let controller = LearningUIFixtureController(rootPath: root.path)
            await controller.load()
            let document = try XCTUnwrap(controller.library?.selectedDocument)
            let run = try XCTUnwrap(LearningStudyRun.plan(map: try XCTUnwrap(document.studyMap.map),
                sessions: document.learning.sessions, now: Date()))
            document.beginStudyRun(run)
            await document.learning.waitForOperation()
            document.learning.answerDraft = "fixture correct"
            document.learning.submitAnswer()
            await document.learning.waitForOperation()
            document.learning.advance()
            XCTAssertTrue(document.canAdvanceStudyRun)
            let map = document.studyMap.map
            let pdf = document.pdfDocument
            if removePage { pdf.removePage(at: 1) }
            else {
                // Keep the saved first-page lesson usable; a different page
                // still invalidates the plan's whole-document snapshot.
                let replacement = try XCTUnwrap(try LearningUIFixture.makePDF().page(at: 0)?.copy() as? PDFPage)
                pdf.removePage(at: 1); pdf.insert(replacement, at: 1)
            }
            XCTAssertFalse(document.canAdvanceStudyRun)
            XCTAssertFalse(document.advanceStudyRun())
            let lesson = try XCTUnwrap(document.learning.sessions.first { $0.phase == .practice })
            document.learning.select(lesson.id)
            let sessions = document.learning.sessions
            XCTAssertNil(document.selectedSourceReviewPage)
            let recovery = try XCTUnwrap(document.studyRunRecovery(for: run))
            XCTAssertEqual(recovery.blocker, .changedSource)
            XCTAssertEqual(recovery.pageIndex, removePage ? 0 : 1)
            document.reviewStudyRunSource()
            XCTAssertEqual(document.notesPageIndex, removePage ? 0 : 1)
            XCTAssertEqual(document.learning.sessions, sessions) // No help flag on the unrelated current answer.
            XCTAssertEqual(document.studyMap.map, map)
            document.continueStudyRun()
            XCTAssertEqual(document.learning.sessions, sessions)
            XCTAssertEqual(document.studyMap.map, map)
            XCTAssertFalse(document.learning.isBusy)
        }
    }

    func testChangedOrMissingRequirementRecoveryRetainsPinnedWorkWithoutResuming() throws {
        for missing in [false, true] {
            let pdf = try LearningUIFixture.makePDF()
            var workspace = try LearningUIFixture.makeWorkspace(document: pdf, url: URL(fileURLWithPath: "/tmp/authored-run-requirement.pdf"))
            var map = try XCTUnwrap(workspace.learningStudyMap)
            let saved = try XCTUnwrap(workspace.learningSessions.first { $0.phase == .practice })
            let target = try XCTUnwrap(saved.studyTarget)
            let index = try XCTUnwrap(map.units.firstIndex { $0.learningTargets.contains { $0.id == target.id } })
            let item = LearningStudyRun.Item(unitID: map.units[index].id, title: map.units[index].title, target: target,
                mode: .lesson, existingSessionID: saved.id, earlierAttemptIDs: saved.attempts.map(\.id))
            var run = LearningStudyRun(pageSignatures: map.pageSignatures, items: [item], startedAt: now)
            run.pause(at: now)
            if missing { map.units.remove(at: index); map.course = nil }
            else {
                let changed = LearningStudyTarget(id: target.id, unitID: target.unitID, kind: target.kind,
                    objective: "A revised requirement, not the saved plan's task.")
                map.units[index] = replacingTargets(map.units[index], with: [changed])
            }
            map.studyRuns = [run]; workspace.learningStudyMap = map
            let document = LearningDocument(workspace: workspace, document: pdf, bookmarkData: nil)
            document.learning.select(saved.id)
            let recovery = try XCTUnwrap(document.studyRunRecovery(for: run))
            XCTAssertEqual(recovery.blocker, .changedRequirement)
            XCTAssertEqual(recovery.pageIndex, 0)
            XCTAssertEqual(recovery.savedSessionID, saved.id)
            document.continueStudyRun(); document.inspectStudyRunWork()
            XCTAssertEqual(document.learning.selectedSessionID, saved.id)
            XCTAssertEqual(document.studyMap.map, map)
            XCTAssertEqual(document.learning.sessions, workspace.learningSessions)
            XCTAssertFalse(document.learning.isBusy)
            XCTAssertFalse(document.advanceStudyRun())
        }
    }

    func testReviewOnlyCoordinatorStopsWithoutOpeningNewWorkAndPersistsItsRecord() async throws {
        // Match the learning sidecar's numeric date encoding precision.
        func persisted<Value: Codable>(_ value: Value) throws -> Value {
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
            return try decoder.decode(Value.self, from: encoder.encode(value))
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cauchy-ui-fixture-review-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = LearningUIFixtureController(rootPath: root.path)
        await controller.load()
        let document = try XCTUnwrap(controller.library?.selectedDocument)
        let originalLesson = try XCTUnwrap(document.learning.sessions.first { $0.phase == .practice })
        let map = try XCTUnwrap(document.studyMap.map)
        let run = try XCTUnwrap(LearningStudyRun.plan(map: map, sessions: document.learning.sessions, focus: .reviewOnly, now: Date()))
        XCTAssertEqual(run.items.count, 1)
        document.beginStudyRun(run)
        await document.learning.waitForOperation()
        document.learning.answerDraft = "Unsent review-only reasoning"
        document.pauseStudyRun()
        try await controller.flush()

        let restarted = LearningUIFixtureController(rootPath: root.path)
        await restarted.load()
        let restored = try XCTUnwrap(restarted.library?.selectedDocument)
        restored.continueStudyRun()
        XCTAssertEqual(restored.learning.answerDraft, "Unsent review-only reasoning")
        XCTAssertEqual(restored.selectedStudyRun?.id, run.id)
        restored.learning.answerDraft = "fixture correct"
        restored.learning.submitAnswer()
        await restored.learning.waitForOperation()
        restored.learning.advance()
        XCTAssertTrue(restored.advanceStudyRun())
        XCTAssertEqual(restored.studyMap.currentStudyRun?.state, .finished)
        XCTAssertEqual(restored.studyMap.currentStudyRun?.attemptedCount, 1)
        XCTAssertEqual(restored.learning.sessions.first { $0.id == originalLesson.id }, try persisted(originalLesson))
        XCTAssertEqual(restored.learning.session?.studyTarget?.id, run.items[0].target.id)
        XCTAssertEqual(restored.learning.sessions.count, 3)
        XCTAssertNil(LearningStudyRun.plan(map: map, sessions: restored.learning.sessions, focus: .reviewOnly, now: Date()))
        try await restarted.flush()
        let finished = LearningUIFixtureController(rootPath: root.path)
        await finished.load()
        XCTAssertEqual(finished.library?.selectedDocument?.studyMap.currentStudyRun, try persisted(restored.studyMap.currentStudyRun))
    }

    func testCoordinatorStopsAfterTheLastPlannedRequirementWithoutStartingAnotherLesson() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cauchy-ui-fixture-run-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = LearningUIFixtureController(rootPath: root.path)
        await controller.load()
        let document = try XCTUnwrap(controller.library?.selectedDocument)
        let run = try XCTUnwrap(LearningStudyRun.plan(map: try XCTUnwrap(document.studyMap.map), sessions: document.learning.sessions, count: 2, now: Date()))
        document.beginStudyRun(run)
        await document.learning.waitForOperation()
        for index in 0..<2 {
            if document.learning.session?.phase == .practice {
                document.learning.answerDraft = "fixture correct"
                document.learning.submitAnswer()
                await document.learning.waitForOperation()
                document.learning.advance()
            }
            XCTAssertEqual(document.learning.session?.phase, .exitCheck)
            document.learning.answerDraft = "fixture correct"
            document.learning.submitAnswer()
            await document.learning.waitForOperation()
            document.learning.advance()
            XCTAssertTrue(document.advanceStudyRun())
            XCTAssertEqual(document.studyMap.currentStudyRun?.attemptedCount, index + 1)
        }
        let finished = try XCTUnwrap(document.studyMap.currentStudyRun)
        XCTAssertEqual(finished.state, .finished)
        XCTAssertNotNil(finished.endedAt)
        XCTAssertNil(finished.currentItem)
        XCTAssertTrue(finished.items.allSatisfy { $0.outcome?.independentCorrect == true })
        XCTAssertEqual(document.learning.sessions.count, 3)
        XCTAssertFalse(document.learning.isBusy)
        XCTAssertFalse(document.advanceStudyRun())
        XCTAssertEqual(document.studyMap.currentStudyRun, finished)
        try await controller.flush()
    }

    func testCoordinatorResumesExactDelayedDraftAfterPersistenceRestartThenOpensTheSavedLesson() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cauchy-ui-fixture-run-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = LearningUIFixtureController(rootPath: root.path)
        await controller.load()
        let document = try XCTUnwrap(controller.library?.selectedDocument)
        let originalLesson = try XCTUnwrap(document.learning.sessions.first { $0.delayedReview == nil && $0.phase == .practice })
        let run = try XCTUnwrap(LearningStudyRun.plan(map: try XCTUnwrap(document.studyMap.map), sessions: document.learning.sessions, count: 2, now: Date()))
        document.beginStudyRun(run)
        await document.learning.waitForOperation()
        let selected = try XCTUnwrap(document.learning.session)
        XCTAssertEqual(selected.studyRunItemID, run.items[0].id)
        XCTAssertEqual(selected.studyTarget?.kind, .application)
        document.learning.answerDraft = "Unsent delayed reasoning"
        document.pauseStudyRun()
        try await controller.flush()

        let restarted = LearningUIFixtureController(rootPath: root.path)
        await restarted.load()
        let restored = try XCTUnwrap(restarted.library?.selectedDocument)
        XCTAssertEqual(restored.studyMap.currentStudyRun?.id, run.id)
        XCTAssertEqual(restored.studyMap.currentStudyRun?.state, .paused)
        restored.continueStudyRun()
        XCTAssertEqual(restored.learning.session?.id, selected.id)
        XCTAssertEqual(restored.learning.session?.answerDraft, "Unsent delayed reasoning")
        XCTAssertEqual(restored.selectedStudyRun?.id, run.id)
        restored.learning.answerDraft = "fixture correct"
        restored.learning.submitAnswer()
        await restored.learning.waitForOperation()
        restored.learning.advance()
        XCTAssertTrue(restored.canAdvanceStudyRun)
        XCTAssertTrue(restored.advanceStudyRun())
        XCTAssertEqual(restored.studyMap.currentStudyRun?.currentIndex, 1)
        XCTAssertEqual(restored.learning.session?.id, originalLesson.id)
        XCTAssertEqual(restored.learning.session?.answerDraft, originalLesson.answerDraft)
        XCTAssertEqual(restored.learning.session?.hintsRevealed, originalLesson.hintsRevealed)
        let beforeFinish = restored.learning.sessions
        restored.finishStudyRun()
        XCTAssertEqual(restored.learning.sessions, beforeFinish)
        XCTAssertEqual(restored.studyMap.currentStudyRun?.attemptedCount, 1)
        XCTAssertNil(restored.studyMap.currentStudyRun?.items[1].outcome)
        XCTAssertEqual(restored.studyMap.currentStudyRun?.state, .finished)
        try await restarted.flush()
    }

    func testCoordinatorFinishesHelpedAndUncertainWorkWithoutAdvancingOrChangingAssessments() async throws {
        for (answer, helped) in [("fixture correct", true), ("fixture uncertain", false)] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("cauchy-ui-fixture-run-\(UUID())")
            defer { try? FileManager.default.removeItem(at: root) }
            let controller = LearningUIFixtureController(rootPath: root.path)
            await controller.load()
            let document = try XCTUnwrap(controller.library?.selectedDocument)
            let run = try XCTUnwrap(LearningStudyRun.plan(map: try XCTUnwrap(document.studyMap.map), sessions: document.learning.sessions, now: Date()))
            document.beginStudyRun(run)
            await document.learning.waitForOperation()
            document.learning.answerDraft = answer
            document.learning.outsideHelpUsed = helped
            document.learning.submitAnswer()
            await document.learning.waitForOperation()
            document.learning.advance()
            XCTAssertFalse(document.canAdvanceStudyRun)
            XCTAssertFalse(document.advanceStudyRun())
            let before = document.learning.sessions
            document.finishStudyRun()
            XCTAssertEqual(document.learning.sessions, before)
            let outcome = try XCTUnwrap(document.studyMap.currentStudyRun?.items[0].outcome)
            XCTAssertFalse(outcome.independentCorrect)
            XCTAssertEqual(outcome.grade, helped ? .correct : .uncertain)
            XCTAssertEqual(outcome.assistanceUsed, helped)
            XCTAssertEqual(document.studyMap.currentStudyRun?.attemptedCount, 1)
            try await controller.flush()
        }
    }

    func testCoordinatorKeepsBlockedSourceInContextWithoutGeneratingOrSkipping() throws {
        let pdf = try LearningUIFixture.makePDF()
        var workspace = try LearningUIFixture.makeWorkspace(document: pdf, url: URL(fileURLWithPath: "/tmp/authored.pdf"))
        var map = try XCTUnwrap(workspace.learningStudyMap)
        let blocked = try XCTUnwrap(map.units.first { $0.id == LearningUIFixture.blockedID })
        map.course = .init(title: "Blocked", overview: "Authored", modules: [.init(title: "Source review", goal: "Inspect", unitIDs: [blocked.id])], connections: [])
        workspace.learningStudyMap = map
        let document = LearningDocument(workspace: workspace, document: pdf, bookmarkData: nil)
        let run = try XCTUnwrap(LearningStudyRun.plan(map: map, sessions: workspace.learningSessions, now: Date()))
        // Remove the unrelated due review so the planned stop is the source issue.
        let blockedRun = LearningStudyRun(pageSignatures: run.pageSignatures, items: run.items.filter { $0.unitID == blocked.id }, startedAt: Date())
        document.beginStudyRun(blockedRun)
        XCTAssertEqual(document.notesPageIndex, blocked.anchorPage)
        XCTAssertTrue(document.notesVisible)
        XCTAssertFalse(document.learning.isBusy)
        XCTAssertEqual(document.learning.sessions, workspace.learningSessions)
        document.finishStudyRun()
        XCTAssertEqual(document.studyMap.currentStudyRun?.attemptedCount, 0)
    }

    func testRebuildingChangedNotesRetainsThePlanAsBlockedHistory() async throws {
        var map = map()
        let run = try XCTUnwrap(LearningStudyRun.plan(map: map, sessions: [], now: now))
        var finished = run
        finished.id = UUID()
        let saved = session(target: finished.items[0].target, itemID: finished.items[0].id, helped: true)
        finished.finish(sessions: [saved], at: now)
        finished.summaryAcknowledgedAt = now
        map.studyRuns = [finished, run]
        let planner = FailingStudyRunPlanner()
        let vm = LearningStudyMapViewModel(map: map, makePlanner: { planner })
        vm.build(document: try LearningUIFixture.makePDF())
        await vm.waitForOperation()
        XCTAssertNil(vm.map?.course)
        XCTAssertEqual(vm.map?.unresolvedPages.count, 2)
        XCTAssertEqual(vm.map?.studyRuns, [finished, run])
        let restored = try JSONDecoder().decode(LearningStudyMap.self, from: JSONEncoder().encode(try XCTUnwrap(vm.map)))
        XCTAssertEqual(restored.studyRuns?.filter { $0.state == .finished }, [finished])
        XCTAssertEqual(restored.studyRuns?.first?.items[0].outcome?.attemptID, saved.latestExitAttempt?.id)
        XCTAssertTrue(restored.studyRuns?.first?.items[0].outcome?.assistanceUsed == true)
        XCTAssertEqual(run.blocker(in: try XCTUnwrap(vm.map), sessions: []), .changedSource)
    }
#endif
}
