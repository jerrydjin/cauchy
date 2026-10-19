import XCTest
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
    func testRebuildingChangedNotesRetainsThePlanAsBlockedHistory() async throws {
        var map = map()
        let run = try XCTUnwrap(LearningStudyRun.plan(map: map, sessions: [], now: now))
        map.studyRuns = [run]
        let planner = FailingStudyRunPlanner()
        let vm = LearningStudyMapViewModel(map: map, makePlanner: { planner })
        vm.build(document: try LearningUIFixture.makePDF())
        await vm.waitForOperation()
        XCTAssertNil(vm.map?.course)
        XCTAssertEqual(vm.map?.unresolvedPages.count, 2)
        XCTAssertEqual(vm.map?.studyRuns, [run])
        XCTAssertEqual(run.blocker(in: try XCTUnwrap(vm.map), sessions: []), .changedSource)
    }
#endif
}
