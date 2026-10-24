import AppKit
import PDFKit
import XCTest
@testable import Cauchy

private let studyText = """
Definition. A linear map preserves vector addition and scalar multiplication.
Theorem. Every linear map sends the zero vector to the zero vector.
Proof. Let T be linear. Scalar preservation gives T(0v) = 0T(v), so T(0) = 0.
Example. Translation by a nonzero vector fails the zero-vector condition.
"""
private let studyQuote = "Every linear map sends the zero vector to the zero vector."
private let proofQuote = "Scalar preservation gives T(0v) = 0T(v), so T(0) = 0."
private let proofRubric = ["Use the assumption of linearity", "Justify the equality with scalar preservation", "Conclude that the image of zero is zero"]

private func planResponse(source: LearningSource, core: [Int], proof: Bool = true, gaps: [String] = []) -> LearningStudyPlanResponse {
    let anchor = core[0]
    let kinds: [LearningStudyKind] = proof ? [.concept, .proof, .application] : [.concept, .application]
    return .init(units: [.init(title: "Linear maps and zero", anchorPage: anchor + 1, sourceQuote: studyQuote,
        pageNumbers: core.map { $0 + 1 }, prerequisites: ["Vector space scalar multiplication"], proofRequired: true,
        proofQuote: proof ? proofQuote : nil, gaps: gaps,
        targets: kinds.map { .init(kind: $0, objective: "\($0.rawValue): explain the zero-vector condition") })],
        pages: core.map { .init(pageNumber: $0 + 1, status: .mapped, reason: "The definition, claim and argument are inventoried.", sourceQuote: studyQuote) })
}

@MainActor
private func studyPDF(pages: Int, extra: String = "") throws -> PDFDocument {
    let data = NSMutableData()
    var bounds = CGRect(x: 0, y: 0, width: 600, height: 800)
    let consumer = try XCTUnwrap(CGDataConsumer(data: data))
    let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &bounds, nil))
    for _ in 0..<pages {
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSAttributedString(string: studyText + extra, attributes: [.font: NSFont.systemFont(ofSize: 12)])
            .draw(in: CGRect(x: 30, y: 400, width: 530, height: 340))
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
    }
    context.closePDF()
    return try XCTUnwrap(PDFDocument(data: data as Data))
}

@MainActor
private final class ProofTutorStub: LearningTutorProtocol {
    var providerID = "fixture"
    var modelID: String? = "fixture-model"
    var lesson: LearningLesson
    var assessment: LearningAssessment
    var freshQuestion: LearningQuestion?
    var excluded: [String] = []
    var holdFreshQuestion = false
    var questionContinuation: CheckedContinuation<LearningQuestion, Never>?
    init(lesson: LearningLesson, assessment: LearningAssessment) { self.lesson = lesson; self.assessment = assessment }
    func makeLesson(source: LearningSource) async throws -> LearningLesson { lesson }
    func assess(question: LearningQuestion, answer: String, source: LearningSource) async throws -> LearningAssessment { assessment }
    func newExitQuestion(lesson: LearningLesson, source: LearningSource, previous: [String]) async throws -> LearningQuestion {
        excluded = previous
        if holdFreshQuestion { return await withCheckedContinuation { questionContinuation = $0 } }
        return freshQuestion ?? lesson.exitCheck
    }
}

@MainActor
private final class StudyPlannerStub: LearningStudyPlannerProtocol {
    var providerID = "fixture"
    var modelID: String? = "fixture-model"
    var sourceLimit = 14_000
    var calls = 0
    var failCall: Int?
    var rejectBatches = false
    var timeOutBatches = false
    var structuredTimeout = false
    var needsRepair = false
    var repairNotes: [String] = []
    var rejectedPages: Set<Int> = []
    var delay = false
    var continuation: CheckedContinuation<LearningStudyPlanResponse, Never>?
    var delayedResponse: LearningStudyPlanResponse?
    var courseCalls = 0
    var failCourse = false
    var delayCourse = false
    var courseContinuation: CheckedContinuation<LearningCourse, Never>?
    var delayedCourse: LearningCourse?
    var missingProof = false

    func plan(source: LearningSource, corePages: [Int], repairNote: String?) async throws -> LearningStudyPlanResponse {
        if needsRepair && repairNote == nil {
            throw LearningStudyValidationError(reason: "A proof quote must be copied literally from its PDF page.")
        }
        if let repairNote { repairNotes.append(repairNote) }
        return try await plan(source: source, corePages: corePages)
    }

    func course(units: [LearningStudyUnit]) async throws -> LearningCourse {
        courseCalls += 1
        if failCourse { throw LearningError.invalidCourse }
        let course = LearningCourse(title: "Linear maps", overview: "Connect definitions and their consequences.",
            modules: [.init(title: "Foundations", goal: "Use linearity to justify the zero condition.", unitIDs: units.map(\.id))],
            connections: units.count > 1 ? [.init(fromUnitID: units[0].id, toUnitID: units[1].id, reason: "Use the earlier definition in the later argument.")] : [])
        if delayCourse {
            delayedCourse = course
            return await withCheckedContinuation { courseContinuation = $0 }
        }
        return course
    }

    func plan(source: LearningSource, corePages: [Int]) async throws -> LearningStudyPlanResponse {
        calls += 1
        if timeOutBatches && corePages.count > 1 {
            if structuredTimeout { throw AssistantFailure.timedOut(.codex) }
            throw CLIAgentError.timedOut
        }
        if failCall == calls { throw ReadingAssistantError.api("Fixture transport failure") }
        if (rejectBatches && corePages.count > 1) || !rejectedPages.isDisjoint(with: corePages) {
            throw LearningError.invalidStudyMap
        }
        let response = planResponse(source: source, core: corePages, proof: !missingProof,
                                    gaps: missingProof ? ["The proof is absent from the local excerpt."] : [])
        if delay {
            delayedResponse = response
            return await withCheckedContinuation { continuation = $0 }
        }
        return response
    }
}

@MainActor
private final class ConcurrentStudyPlannerStub: LearningStudyPlannerProtocol {
    var providerID = "fixture"
    var modelID: String? = "fixture-model"
    var sourceLimit = 14_000
    var parallelism = 3
    var active = 0
    var peak = 0
    var courseCalls = 0
    var replies: [Int: (LearningStudyPlanResponse, CheckedContinuation<LearningStudyPlanResponse, Never>)] = [:]

    func plan(source: LearningSource, corePages: [Int]) async throws -> LearningStudyPlanResponse {
        active += 1
        peak = max(peak, active)
        let response = planResponse(source: source, core: corePages)
        let result = await withCheckedContinuation { replies[corePages[0]] = (response, $0) }
        active -= 1
        return result
    }

    func complete(_ page: Int) {
        guard let (response, continuation) = replies.removeValue(forKey: page) else { return }
        continuation.resume(returning: response)
    }

    func course(units: [LearningStudyUnit]) async throws -> LearningCourse {
        courseCalls += 1
        return .init(title: "Connected notes", overview: "The entire inventory is included.",
            modules: [.init(title: "Foundations", goal: "Connect the concepts.", unitIDs: units.map(\.id))], connections: [])
    }
}

@MainActor
final class LearningStudyMapTests: XCTestCase {
    private var source: LearningSource { .init(passages: [.init(pageIndex: 0, text: studyText)]) }

    func testGoalRevisionsKeepEvidenceAndSchedulesSeparateEvenWhenWordingIsRestored() async throws {
        let pdf = try studyPDF(pages: 1)
        let vm = LearningStudyMapViewModel { StudyPlannerStub() }
        vm.build(document: pdf); await vm.waitForOperation()
        let initial = try XCTUnwrap(vm.map)
        let unit = try XCTUnwrap(initial.units.first)
        let clock = Date(timeIntervalSince1970: 1_800_000_000)
        for original in unit.learningTargets {
            var saved = passedSession(target: original); saved.reviewDueAt = clock
            let pinned = LearningStudyRun(pageSignatures: initial.pageSignatures,
                items: [.init(unitID: unit.id, title: unit.title, target: original, mode: .lesson,
                              existingSessionID: saved.id, earlierAttemptIDs: saved.attempts.map(\.id))], startedAt: clock)
            let before = try XCTUnwrap(vm.map?.units.first)
            try vm.reviseGoal(original, in: before, objective: "Revised: " + original.objective,
                note: "Correct an inaccurate generated goal.", document: pdf, at: clock)
            var currentUnit = try XCTUnwrap(vm.map?.units.first)
            let revised = try XCTUnwrap(currentUnit.learningTargets.first { $0.id == original.id })
            XCTAssertNotNil(revised.revisionID)
            XCTAssertFalse(original.matchesRequirement(revised))
            XCTAssertNil(currentUnit.evidence(for: revised, sessions: [saved]))
            XCTAssertNil(currentUnit.evidence(for: original, sessions: [saved]))
            XCTAssertNil(vm.map?.nextDelayedReview(sessions: [saved], now: clock, targetID: original.id))
            XCTAssertEqual(pinned.blocker(in: vm.map!, sessions: [saved]), .changedRequirement)
            XCTAssertEqual(pinned.currentItem?.session(in: [saved]), saved)
            XCTAssertEqual(LearningRequirementHistory.sessions(for: revised, in: [saved]), [saved])
            try vm.reviseGoal(revised, in: currentUnit, objective: original.objective,
                note: "Restore the wording, retaining both revision decisions.", document: pdf, at: clock)
            currentUnit = try XCTUnwrap(vm.map?.units.first)
            let restored = try XCTUnwrap(currentUnit.learningTargets.first { $0.id == original.id })
            XCTAssertEqual(restored.objective, original.objective)
            XCTAssertFalse(restored.matchesRequirement(original))
            XCTAssertFalse(restored.matchesRequirement(revised))
            XCTAssertNil(currentUnit.evidence(for: restored, sessions: [saved]))
            XCTAssertTrue(currentUnit.evidence(for: restored, sessions: [passedSession(target: restored)])?.hasIndependentCorrectResult == true)
            let exported = try XCTUnwrap(LearningRequirementHistoryExport.markdown(documentTitle: "Fixture", target: restored,
                sessions: [saved], sourceIsCurrent: { _ in true }))
            XCTAssertTrue(exported.contains("Earlier requirement version"))
            XCTAssertTrue(exported.contains("does not establish the current requirement"))
            var contextOnly = restored; contextOnly.courseContext = "A reorganized chapter"
            XCTAssertTrue(contextOnly.matchesRequirement(restored))
        }
        XCTAssertEqual(vm.map?.units.first?.targets, unit.targets)
        XCTAssertEqual(vm.map?.units.first?.goalRevisions?.count, 6)
        let data = try JSONEncoder().encode(vm.map)
        XCTAssertEqual(try JSONDecoder().decode(LearningStudyMap.self, from: data).units, vm.map?.units)
        let legacy = try JSONDecoder().decode(LearningStudyMap.self, from: JSONEncoder().encode(initial))
        XCTAssertNil(legacy.units.first?.goalRevisions)
        XCTAssertNil(legacy.units.first?.targets.first?.revisionID)
    }

    func testGoalRevisionRetainsSourceAndSyllabusObligationsIncludingReconciledProofs() throws {
        let pdf = try studyPDF(pages: 1)
        var unit = try XCTUnwrap(LearningStudyPlannerService.validate(planResponse(source: source, core: [0], proof: false,
            gaps: ["The proof is absent from the local excerpt."]), source: source, corePages: [0]).first)
        let response = LearningReconciliationResponse(issues: [.init(gapIndex: 0, disposition: .foundElsewhere,
            explanation: "Found the supplied scalar argument.", evidence: [.init(pageIndex: 0, quote: proofQuote)])],
            requestedPages: [], proofObjective: "Prove the zero-vector property using scalar preservation.",
            proofEvidence: [.init(pageIndex: 0, quote: proofQuote)])
        unit.reconciliation = try LearningSourceReconciler.validate(response, unit: unit, source: source,
            pageCount: 1, providerID: "fixture", modelID: nil)
        let signatures = (0..<pdf.pageCount).map { LearningStudyInput.signature(pdf.page(at: $0)?.string ?? "") }
        let vm = LearningStudyMapViewModel(map: .init(pageSignatures: signatures, pages: [], units: [unit]))
        let proof = try XCTUnwrap(unit.learningTargets.first { $0.kind == .proof })
        try vm.addSyllabusRequirements("Zero preservation", kinds: [.proof], provenance: "Authored syllabus")
        let obligation = try XCTUnwrap(vm.map?.syllabus?.requirements.first)
        try vm.mapSyllabusRequirement(obligation.id, kind: .proof, targetIDs: [proof.id], status: .mapped, note: "Original source mapping")
        let syllabus = vm.map?.syllabus
        try vm.reviseGoal(proof, in: unit, objective: "Justify every inference in the scalar-zero argument.",
            note: "The generated goal omitted the inference justification.", document: pdf)
        let current = try XCTUnwrap(vm.map?.units.first)
        XCTAssertEqual(current.reconciliation, unit.reconciliation)
        XCTAssertEqual(current.targets, unit.targets)
        XCTAssertEqual(current.learningTargets.count, unit.learningTargets.count)
        XCTAssertEqual(current.learningTargets.last?.kind, .proof)
        XCTAssertEqual(current.proofRequired, unit.proofRequired)
        XCTAssertEqual(current.gaps, unit.gaps)
        XCTAssertEqual(vm.map?.syllabus, syllabus)
        XCTAssertEqual(vm.map?.syllabus?.coverage(in: vm.map!, sessions: []).sourceMapped, 0)
        XCTAssertEqual(vm.map?.syllabus?.coverage(in: vm.map!, sessions: []).required, 1)
        var blocked = current; blocked.pendingSourceCorrection = true
        let blockedVM = LearningStudyMapViewModel(map: .init(pageSignatures: signatures, pages: [], units: [blocked]))
        let target = try XCTUnwrap(blocked.learningTargets.last)
        try blockedVM.reviseGoal(target, in: blocked, objective: "Retain the complete proof and its assumptions.", note: "Refine wording only.", document: pdf)
        XCTAssertTrue(blockedVM.map!.units[0].needsSourceReview)
        XCTAssertEqual(blockedVM.map!.units[0].openGapCount, 1)
        XCTAssertEqual(blockedVM.map!.units[0].reconciliation, blocked.reconciliation)
        XCTAssertFalse(blockedVM.map!.units[0].hasEvidenceForEveryTarget(sessions: []))
    }

    func testGoalRevisionRejectsInvalidStaleBusyAndChangedSourceEditsWithoutSaving() async throws {
        let pdf = try studyPDF(pages: 1)
        let planner = StudyPlannerStub()
        let vm = LearningStudyMapViewModel { planner }
        vm.build(document: pdf); await vm.waitForOperation()
        let unit = try XCTUnwrap(vm.map?.units.first)
        let target = unit.learningTargets[0]
        var writes = 0; vm.onChange = { _ in writes += 1 }
        let before = vm.map
        for (objective, note) in [(" ", "Reason"), (target.objective + "  ", "Reason"),
            (String(repeating: "x", count: 2_001), "Reason"), ("Changed wording", "  "),
            ("Changed wording", String(repeating: "x", count: 2_001))] {
            XCTAssertThrowsError(try vm.reviseGoal(target, in: unit, objective: objective, note: note, document: pdf))
        }
        var fake = target; fake.revisionID = UUID()
        XCTAssertThrowsError(try vm.reviseGoal(fake, in: unit, objective: "Changed wording", note: "Reason", document: pdf))
        var stale = unit; stale.pendingSourceCorrection = true
        XCTAssertThrowsError(try vm.reviseGoal(target, in: stale, objective: "Changed wording", note: "Reason", document: pdf))
        XCTAssertThrowsError(try vm.reviseGoal(target, in: unit, objective: "Changed wording", note: "Reason",
            document: studyPDF(pages: 1, extra: "Changed actual PDF text.")))
        vm.build(document: pdf)
        XCTAssertThrowsError(try vm.reviseGoal(target, in: unit, objective: "Changed wording", note: "Reason", document: pdf))
        vm.cancel(); await vm.waitForOperation()
        XCTAssertEqual(vm.map, before)
        XCTAssertEqual(writes, 0)
        try vm.reviseGoal(target, in: unit, objective: "A valid revised goal", note: "A valid reason", document: pdf)
        let revised = vm.map
        XCTAssertEqual(writes, 1)
        XCTAssertThrowsError(try vm.reviseGoal(target, in: unit, objective: "A stale second edit", note: "Reason", document: pdf))
        XCTAssertEqual(vm.map, revised)
        XCTAssertEqual(writes, 1)
    }

    func testRebuildingSourceRetainsGoalRevisionProvenanceWithoutApplyingItToNewRequirements() async throws {
        let pdf = try studyPDF(pages: 1)
        let vm = LearningStudyMapViewModel { StudyPlannerStub() }
        vm.build(document: pdf); await vm.waitForOperation()
        let unit = try XCTUnwrap(vm.map?.units.first)
        try vm.reviseGoal(unit.learningTargets[0], in: unit, objective: "Correct this source-supported goal.", note: "Retain the decision.", document: pdf)
        let edited = try XCTUnwrap(vm.map?.units.first)
        // An unresolved page can be remapped without erasing edits to an unchanged requirement.
        var pendingMap = try XCTUnwrap(vm.map); pendingMap.pages[0].status = .pending
        let resumed = LearningStudyMapViewModel(map: pendingMap) { StudyPlannerStub() }
        resumed.build(document: pdf); await resumed.waitForOperation()
        XCTAssertEqual(resumed.map?.units.first?.goalRevisions, edited.goalRevisions)
        XCTAssertEqual(resumed.map?.units.first?.learningTargets, edited.learningTargets)
        let changed = try studyPDF(pages: 1, extra: "A changed source with a new condition.")
        resumed.build(document: changed); await resumed.waitForOperation()
        XCTAssertEqual(resumed.map?.earlierGoalRevisions, edited.goalRevisions)
        XCTAssertTrue(resumed.map!.units.allSatisfy { $0.goalRevisions == nil })
        XCTAssertFalse(resumed.map!.units.flatMap(\.learningTargets).contains { $0.revisionID != nil })
        resumed.build(document: changed); await resumed.waitForOperation()
        XCTAssertEqual(resumed.map?.earlierGoalRevisions?.count, 1)
    }

    func testGoalHistoryDistinguishesCurrentEarlierAndUnappliedDecisionsWithoutAComposedCourse() throws {
        var unit = try XCTUnwrap(LearningStudyPlannerService.validate(planResponse(source: source, core: [0]), source: source, corePages: [0]).first)
        let original = unit.targets[0]
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = LearningGoalRevision(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, previous: original,
            objective: "First revised goal", note: "First decision", unitTitle: unit.title, source: unit.teachingAnchor, createdAt: date)
        let latest = LearningGoalRevision(id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, previous: first.target,
            objective: original.objective, note: "Restore wording with a separate version", unitTitle: unit.title, source: unit.teachingAnchor, createdAt: date.addingTimeInterval(1))
        var other = original; other.id = UUID()
        let unapplied = LearningGoalRevision(id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!, previous: other,
            objective: "A requirement no longer inventoried", note: "Retain its decision", unitTitle: unit.title, source: unit.teachingAnchor, createdAt: date)
        unit.goalRevisions = [first, latest, unapplied]
        let archived = LearningGoalRevision(previous: original, objective: "An earlier-source goal", note: "Keep the original source reference",
            unitTitle: unit.title, source: unit.teachingAnchor, createdAt: date.addingTimeInterval(-1))
        let map = LearningStudyMap(pageSignatures: [], pages: [], units: [unit], earlierGoalRevisions: [archived])
        XCTAssertNil(map.course)
        let before = try JSONEncoder().encode(map)
        let entries = LearningGoalHistory.entries(in: map)
        XCTAssertEqual(entries.map(\.id), [latest.id, first.id, unapplied.id, archived.id])
        XCTAssertEqual(entries.map(\.status), [.current, .earlierGoal, .earlierGoal, .earlierSource])
        XCTAssertEqual(entries.last?.revision.source, unit.teachingAnchor)
        XCTAssertEqual(entries.first?.revision.note, latest.note)
        XCTAssertEqual(entries.first?.revision.previous, first.target)
        XCTAssertEqual(unit.learningTargets[0].objective, original.objective)
        XCTAssertEqual(unit.learningTargets[0].revisionID, latest.id)
        XCTAssertEqual(LearningGoalHistory.entries(in: map), entries)
        XCTAssertTrue(LearningGoalHistory.entries(in: .init(pageSignatures: [], pages: [])).isEmpty)
        let roundTrip = try JSONDecoder().decode(LearningStudyMap.self, from: before)
        XCTAssertEqual(LearningGoalHistory.entries(in: roundTrip), entries)
        var remapped = map
        remapped.units[0].goalRevisions = [latest] // Its preceding version is missing: wording alone cannot make it current.
        XCTAssertEqual(LearningGoalHistory.entries(in: remapped).first?.status, .earlierGoal)
    }

    func testSyllabusMapsSeparateObligationsWithoutCreatingLearnerEvidence() throws {
        let unit = try XCTUnwrap(LearningStudyPlannerService.validate(planResponse(source: source, core: [0]), source: source, corePages: [0]).first)
        let vm = LearningStudyMapViewModel(map: .init(pageSignatures: [], pages: [], units: [unit]))
        try vm.addSyllabusRequirements("Linear-map zero preservation\nAn additional syllabus topic missing from the notes",
                                       kinds: [.concept, .proof, .application], provenance: "Authored evaluation syllabus, required outcomes")
        let requirements = try XCTUnwrap(vm.map?.syllabus?.requirements)
        XCTAssertEqual(requirements.count, 2)
        for target in unit.targets {
            try vm.mapSyllabusRequirement(requirements[0].id, kind: target.kind, targetIDs: [target.id], status: .mapped,
                                          note: "The exact target and its supplied argument support this requirement.")
        }
        try vm.mapSyllabusRequirement(requirements[1].id, kind: .proof, targetIDs: [], status: .absent,
                                      note: "Reviewed the supplied notes; no supporting proof is present.")
        let map = try XCTUnwrap(vm.map)
        let syllabus = try XCTUnwrap(map.syllabus)
        let coverage = syllabus.coverage(in: map, sessions: [])
        XCTAssertEqual(coverage.required, 6)
        XCTAssertEqual(coverage.sourceMapped, 3)
        XCTAssertEqual(coverage.checked, 0)
        let concept = try XCTUnwrap(unit.targets.first { $0.kind == .concept })
        XCTAssertEqual(syllabus.coverage(in: map, sessions: [passedSession(target: concept)]).checked, 1)
        let proof = try XCTUnwrap(unit.targets.first { $0.kind == .proof })
        XCTAssertThrowsError(try vm.mapSyllabusRequirement(requirements[1].id, kind: .proof, targetIDs: [concept.id],
                                                          status: .mapped, note: "A concept cannot stand in for a proof."))
        XCTAssertThrowsError(try vm.mapSyllabusRequirement(requirements[0].id, kind: .proof, targetIDs: [proof.id, proof.id],
                                                          status: .mapped, note: "Duplicate targets must be rejected."))
        XCTAssertEqual(vm.map?.syllabus, syllabus)
    }

    func testSyllabusMappingCorrectionsRetainHistoryAndStaleTargetsBecomeUnresolved() throws {
        let unit = try XCTUnwrap(LearningStudyPlannerService.validate(planResponse(source: source, core: [0]), source: source, corePages: [0]).first)
        let vm = LearningStudyMapViewModel(map: .init(pageSignatures: [], pages: [], units: [unit]))
        try vm.addSyllabusRequirements("Prove the zero-vector consequence", kinds: [.proof], provenance: "Course syllabus item 1")
        let requirement = try XCTUnwrap(vm.map?.syllabus?.requirements.first)
        let target = try XCTUnwrap(unit.targets.first { $0.kind == .proof })
        try vm.mapSyllabusRequirement(requirement.id, kind: .proof, targetIDs: [], status: .unresolved, note: "Locate the argument first.")
        let first = try XCTUnwrap(vm.map?.syllabus?.history.first)
        try vm.mapSyllabusRequirement(requirement.id, kind: .proof, targetIDs: [target.id], status: .mapped, note: "Verified the scalar-preservation argument.")
        let map = try XCTUnwrap(vm.map)
        XCTAssertEqual(map.syllabus?.history.first, first)
        XCTAssertEqual(map.syllabus?.history.count, 2)
        XCTAssertEqual(map.syllabus?.coverage(in: map, sessions: []).sourceMapped, 1)
        let restored = try JSONDecoder().decode(LearningStudyMap.self, from: JSONEncoder().encode(map))
        XCTAssertEqual(restored.syllabus, map.syllabus)
        var changed = restored
        changed.units = []
        XCTAssertEqual(changed.syllabus?.requirements, [requirement])
        XCTAssertEqual(changed.syllabus?.coverage(in: changed, sessions: []).sourceMapped, 0)
        changed = restored
        changed.units[0].pendingSourceCorrection = true
        XCTAssertEqual(changed.syllabus?.coverage(in: changed, sessions: []).sourceMapped, 0)
        XCTAssertEqual(changed.syllabus?.history, restored.syllabus?.history)
        XCTAssertThrowsError(try vm.addSyllabusRequirements(requirement.text, kinds: [.proof], provenance: "Duplicate"))
    }

    func testRegeneratingChangedNotesPreservesSyllabusRequirementsAndMappingProvenance() async throws {
        let pdf = try studyPDF(pages: 1)
        let vm = LearningStudyMapViewModel(map: .init(pageSignatures: ["old signature"], pages: [.init(pageIndex: 0)])) { StudyPlannerStub() }
        try vm.addSyllabusRequirements("A required proof\nA required application", kinds: [.proof, .application], provenance: "Explicit syllabus supplied for evaluation")
        let requirements = try XCTUnwrap(vm.map?.syllabus?.requirements)
        try vm.mapSyllabusRequirement(requirements[0].id, kind: .proof, targetIDs: [], status: .absent, note: "Absent from the old notes; retain this requirement.")
        let previous = vm.map?.syllabus
        vm.build(document: pdf); await vm.waitForOperation()
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.map?.syllabus, previous)
        XCTAssertNotNil(vm.map?.course)
        XCTAssertEqual(vm.map?.syllabus?.coverage(in: vm.map!, sessions: []).required, 4)
        XCTAssertEqual(vm.map?.syllabus?.coverage(in: vm.map!, sessions: []).sourceMapped, 0)
    }

    func testDelayedReviewIsDueOnlyAfterSavedTimeAndKeepsEachRequirementSeparate() async throws {
        let unit = try XCTUnwrap(LearningStudyPlannerService.validate(planResponse(source: source, core: [0]), source: source, corePages: [0]).first)
        let map = LearningStudyMap(pageSignatures: [], pages: [.init(pageIndex: 0, status: .mapped)], units: [unit])
        for target in unit.targets {
            var clock = Date(timeIntervalSince1970: 1_700_000_000)
            var immediate = passedSession(target: target)
            immediate.reviewDueAt = clock.addingTimeInterval(86_400)
            immediate.attempts[0].createdAt = clock
            let tutor = ProofTutorStub(lesson: fixtureLesson(), assessment: proofAssessment(outcomes: [.met, .met, .met]))
            tutor.freshQuestion = .init(prompt: "A different delayed \(target.kind.rawValue) question for the exact zero-preservation requirement.",
                expectedAnswer: "Use linearity with the stated hypotheses and justify the zero-vector conclusion.", hints: [],
                kind: target.kind, gradingCriteria: proofRubric)
            let vm = LearningViewModel(now: { clock }, makeTutor: { tutor })
            vm.restore([immediate])
            XCTAssertNil(map.nextDelayedReview(sessions: vm.sessions, now: clock))
            clock = clock.addingTimeInterval(86_400)
            let recommendation = try XCTUnwrap(map.nextDelayedReview(sessions: vm.sessions, now: clock))
            vm.startDelayedReview(recommendation)
            await vm.waitForOperation()
            XCTAssertNil(vm.errorMessage)
            let review = try XCTUnwrap(vm.session)
            XCTAssertNotEqual(review.id, immediate.id)
            XCTAssertEqual(review.studyTarget?.id, target.id)
            XCTAssertEqual(review.question?.kind, target.kind)
            XCTAssertEqual(review.delayedReview?.scheduledFor, immediate.reviewDueAt)
            XCTAssertEqual(review.delayedReview?.startedAt, clock)
            XCTAssertTrue(tutor.excluded.contains(immediate.lesson.exitCheck.prompt))
            vm.answerDraft = "A saved delayed answer draft"
            let restored = LearningViewModel(now: { clock }, makeTutor: { tutor })
            restored.restore(try JSONDecoder().decode([LearningSession].self, from: JSONEncoder().encode(vm.sessions)))
            let next = try XCTUnwrap(map.nextDelayedReview(sessions: restored.sessions, now: clock))
            XCTAssertEqual(next.activeSessionID, review.id)
            restored.startDelayedReview(next)
            XCTAssertEqual(restored.answerDraft, "A saved delayed answer draft")
            restored.submitAnswer(); await restored.waitForOperation(); restored.advance()
            let result = try XCTUnwrap(restored.session)
            XCTAssertEqual(result.reviewDueAt, clock.addingTimeInterval(3 * 86_400))
            XCTAssertEqual(map.delayedEvidence(for: target, sessions: restored.sessions).count, 1)
            XCTAssertEqual(unit.evidence(for: target, sessions: restored.sessions)?.id, immediate.attempts[0].id)
            XCTAssertEqual(restored.sessions.first { $0.id == immediate.id }, immediate)
            for other in unit.targets where other.id != target.id {
                XCTAssertTrue(map.delayedEvidence(for: other, sessions: restored.sessions).isEmpty)
                XCTAssertNil(unit.evidence(for: other, sessions: restored.sessions))
            }
        }
    }

    func testStaleDelayedReviewActionResumesSavedDraftInsteadOfDuplicatingIt() async throws {
        let unit = try XCTUnwrap(LearningStudyPlannerService.validate(planResponse(source: source, core: [0]), source: source, corePages: [0]).first)
        let clock = Date(timeIntervalSince1970: 1_700_100_000)
        let map = LearningStudyMap(pageSignatures: [], pages: [.init(pageIndex: 0, status: .mapped)], units: [unit])
        for target in unit.targets {
            var immediate = passedSession(target: target); immediate.reviewDueAt = clock
            let tutor = ProofTutorStub(lesson: fixtureLesson(), assessment: proofAssessment(outcomes: [.met, .met, .met]))
            tutor.freshQuestion = .init(prompt: "A different delayed question about zero preservation in a new representation.",
                expectedAnswer: "Use scalar preservation with scalar zero.", hints: [], kind: target.kind, gradingCriteria: proofRubric)
            var requests = 0
            let vm = LearningViewModel(now: { clock }, makeTutor: { requests += 1; return tutor })
            vm.restore([immediate])
            let earlierAction = try XCTUnwrap(map.nextDelayedReview(sessions: vm.sessions, now: clock))
            vm.startDelayedReview(earlierAction); await vm.waitForOperation()
            vm.answerDraft = "Keep my reasoning in the delayed check that is already open."
            let saved = vm.sessions
            let selected = vm.selectedSessionID
            tutor.freshQuestion = .init(prompt: "Another unused question that should never replace the open delayed check.",
                expectedAnswer: "Apply linearity with the domain hypotheses.", hints: [], kind: target.kind, gradingCriteria: proofRubric)
            vm.showSections()
            var writes = 0; vm.onChange = { _ in writes += 1 }
            vm.startDelayedReview(earlierAction); await vm.waitForOperation()
            XCTAssertEqual(requests, 1)
            XCTAssertEqual(writes, 0)
            XCTAssertEqual(vm.sessions, saved)
            XCTAssertEqual(vm.selectedSessionID, selected)
            XCTAssertEqual(vm.answerDraft, "Keep my reasoning in the delayed check that is already open.")
        }
    }

    func testStaleDelayedReviewCannotRestartCompletedRescheduledOrIneligibleWork() async throws {
        let unit = try XCTUnwrap(LearningStudyPlannerService.validate(planResponse(source: source, core: [0]), source: source, corePages: [0]).first)
        let clock = Date(timeIntervalSince1970: 1_700_100_000)
        let map = LearningStudyMap(pageSignatures: [], pages: [], units: [unit])
        for target in unit.targets {
            var immediate = passedSession(target: target); immediate.reviewDueAt = clock
            immediate.attempts[0].createdAt = clock.addingTimeInterval(-86_400)
            let originalAction = try XCTUnwrap(map.nextDelayedReview(sessions: [immediate], now: clock))
            var completed = immediate
            completed.id = UUID()
            completed.delayedReview = .init(previousSessionID: immediate.id, scheduledFor: clock, startedAt: clock, round: 1)
            completed.attempts[0].createdAt = clock.addingTimeInterval(10)
            completed.reviewDueAt = clock.addingTimeInterval(3 * 86_400)
            var helped = passedSession(target: target, help: true); helped.reviewDueAt = clock
            var rescheduled = immediate; rescheduled.reviewDueAt = clock.addingTimeInterval(86_400)
            for saved in [[completed, immediate], [helped], [rescheduled], []] {
                var requests = 0
                let tutor = ProofTutorStub(lesson: fixtureLesson(), assessment: proofAssessment(outcomes: [.met, .met, .met]))
                let vm = LearningViewModel(now: { clock }, makeTutor: { requests += 1; return tutor })
                vm.restore(try JSONDecoder().decode([LearningSession].self, from: JSONEncoder().encode(saved)))
                var writes = 0; vm.onChange = { _ in writes += 1 }
                vm.startDelayedReview(originalAction); await vm.waitForOperation()
                XCTAssertEqual(vm.sessions, saved)
                XCTAssertEqual(requests, 0)
                XCTAssertEqual(writes, 0)
                XCTAssertNil(vm.selectedSessionID)
                XCTAssertNotNil(vm.errorMessage)
            }
        }
    }

    func testDelayedQuestionRevalidatesCurrentRequirementsAndSourceObligations() async throws {
        let unit = try XCTUnwrap(LearningStudyPlannerService.validate(planResponse(source: source, core: [0]), source: source, corePages: [0]).first)
        let clock = Date(timeIntervalSince1970: 1_700_100_000)
        let map = LearningStudyMap(pageSignatures: [], pages: [], units: [unit])
        for target in unit.targets {
            for change in ["requirement", "source obligation", "removed map", "course organization"] {
                var immediate = passedSession(target: target); immediate.reviewDueAt = clock
                let action = try XCTUnwrap(map.nextDelayedReview(sessions: [immediate], now: clock))
                let tutor = ProofTutorStub(lesson: fixtureLesson(), assessment: proofAssessment(outcomes: [.met, .met, .met]))
                tutor.holdFreshQuestion = true
                let vm = LearningViewModel(now: { clock }, makeTutor: { tutor }); vm.restore([immediate])
                var currentMap: LearningStudyMap? = map
                vm.delayedReviewRecommendation = { [weak vm] id, date in
                    guard let vm else { return nil }
                    return currentMap?.nextDelayedReview(sessions: vm.sessions, now: date, targetID: id)
                }
                var writes = 0; vm.onChange = { _ in writes += 1 }
                vm.startDelayedReview(action)
                for _ in 0..<1_000 where tutor.questionContinuation == nil { await Task.yield() }
                let pending = try XCTUnwrap(tutor.questionContinuation)
                switch change {
                case "requirement":
                    let revised = LearningStudyTarget(id: target.id, unitID: target.unitID, kind: target.kind,
                        objective: target.objective + " with the restricted domain justified")
                    currentMap?.units[0] = .init(id: unit.id, title: unit.title, anchorPage: unit.anchorPage,
                        sourceQuote: unit.sourceQuote, pageIndices: unit.pageIndices, prerequisites: unit.prerequisites,
                        proofRequired: unit.proofRequired, proofQuote: unit.proofQuote, gaps: unit.gaps, targets: [revised])
                case "source obligation": currentMap?.units[0].pendingSourceCorrection = true
                case "removed map": currentMap = nil
                default:
                    currentMap?.course = .init(title: "Reorganized course", overview: "Same requirements.",
                        modules: [.init(title: "New chapter title", goal: "Same ideas", unitIDs: [unit.id])], connections: [])
                }
                let expectedMap = currentMap
                pending.resume(returning: .init(prompt: "A different delayed question about zero preservation with a new representation.",
                    expectedAnswer: "Use scalar preservation with the stated hypotheses.", hints: [], kind: target.kind, gradingCriteria: proofRubric))
                await vm.waitForOperation()
                XCTAssertFalse(vm.isBusy)
                XCTAssertEqual(currentMap, expectedMap)
                XCTAssertEqual(vm.sessions.first { $0.id == immediate.id }, immediate)
                if change == "course organization" {
                    XCTAssertEqual(vm.sessions.count, 2)
                    XCTAssertNil(vm.errorMessage)
                    XCTAssertEqual(writes, 1)
                } else {
                    XCTAssertEqual(vm.sessions, [immediate])
                    XCTAssertNil(vm.selectedSessionID)
                    XCTAssertNotNil(vm.errorMessage)
                    XCTAssertEqual(writes, 0)
                }
            }
        }
    }

    func testSettingAsideExactEvidenceReopensRequirementWithoutRewritingTheRecord() throws {
        let unit = try XCTUnwrap(LearningStudyPlannerService.validate(planResponse(source: source, core: [0]), source: source, corePages: [0]).first)
        let clock = Date(timeIntervalSince1970: 1_900_000_000)
        let map = LearningStudyMap(pageSignatures: [], pages: [], units: [unit])
        for target in unit.targets {
            var saved = passedSession(target: target); saved.reviewDueAt = clock
            saved.attempts[0].createdAt = clock.addingTimeInterval(-86_400)
            var earlier = passedSession(target: target); earlier.attempts[0].createdAt = clock.addingTimeInterval(-3 * 86_400)
            var other = saved; other.id = UUID(); other.studyTarget = nil
            let vm = LearningViewModel(now: { clock }, makeTutor: { XCTFail("Reviewing an assessment must not request a tutor"); return ProofTutorStub(lesson: self.fixtureLesson(), assessment: self.proofAssessment(outcomes: [.met, .met, .met])) })
            vm.restore([saved, earlier, other]); vm.select(other.id)
            var writes = 0; vm.onChange = { _ in writes += 1 }
            vm.setAssessmentAside(true, sessionID: saved.id, attemptID: saved.attempts[0].id)
            var expected = saved; expected.updatedAt = clock; expected.attempts[0].setAsideAt = clock
            XCTAssertEqual(vm.sessions, [expected, earlier, other])
            XCTAssertEqual(vm.selectedSessionID, other.id)
            XCTAssertEqual(writes, 1)
            XCTAssertFalse(expected.passedExitCheck)
            XCTAssertEqual(expected.progressLabel, "Assessment set aside by you")
            XCTAssertEqual(unit.evidence(for: target, sessions: vm.sessions)?.id, saved.attempts[0].id)
            XCTAssertEqual(unit.checkedTargetCount(sessions: vm.sessions), 0)
            XCTAssertNil(map.nextDelayedReview(sessions: vm.sessions, now: clock))
            XCTAssertTrue(map.availableStudyChoices(sessions: vm.sessions).contains { $0.target.id == target.id })
            let entry = try XCTUnwrap(LearningRequirementHistory.entries(for: target, in: vm.sessions).first)
            XCTAssertEqual(entry.setAsideAt, clock)
            XCTAssertEqual(entry.assessment, saved.attempts[0].assessment)
            XCTAssertEqual(entry.status, "Assessment set aside by you")
            vm.setAssessmentAside(true, sessionID: saved.id, attemptID: saved.attempts[0].id)
            vm.setAssessmentAside(true, sessionID: UUID(), attemptID: saved.attempts[0].id)
            vm.setAssessmentAside(true, sessionID: saved.id, attemptID: UUID())
            XCTAssertEqual(writes, 1)
            vm.restore(try JSONDecoder().decode([LearningSession].self, from: JSONEncoder().encode(vm.sessions)))
            vm.select(other.id)
            vm.setAssessmentAside(false, sessionID: saved.id, attemptID: saved.attempts[0].id)
            var reinstated = saved; reinstated.updatedAt = clock
            XCTAssertEqual(vm.sessions, [reinstated, earlier, other])
            XCTAssertEqual(vm.selectedSessionID, other.id)
            XCTAssertEqual(writes, 2)
            XCTAssertEqual(unit.checkedTargetCount(sessions: vm.sessions), 1)
            XCTAssertEqual(map.nextDelayedReview(sessions: vm.sessions, now: clock)?.previous.id, saved.id)
        }
    }

    func testSetAsideDelayedResultCannotTriggerSpacingOrPlanProgressButKeepsHistoricalOutcome() throws {
        let unit = try XCTUnwrap(LearningStudyPlannerService.validate(planResponse(source: source, core: [0]), source: source, corePages: [0]).first)
        let target = unit.targets[0]
        let clock = Date(timeIntervalSince1970: 1_900_000_000)
        var immediate = passedSession(target: target); immediate.reviewDueAt = clock.addingTimeInterval(-86_400)
        immediate.attempts[0].createdAt = clock.addingTimeInterval(-2 * 86_400)
        var delayed = passedSession(target: target)
        delayed.delayedReview = .init(previousSessionID: immediate.id, scheduledFor: clock.addingTimeInterval(-86_400), startedAt: clock, round: 1)
        delayed.reviewDueAt = clock.addingTimeInterval(3 * 86_400); delayed.attempts[0].createdAt = clock
        let map = LearningStudyMap(pageSignatures: [], pages: [], units: [unit])
        var run = LearningStudyRun(pageSignatures: [], items: [.init(unitID: unit.id, title: unit.title, target: target,
            mode: .delayedReview, existingSessionID: delayed.id, earlierAttemptIDs: [])], startedAt: clock)
        XCTAssertTrue(run.advance(map: map, sessions: [immediate, delayed], at: clock))
        let originalRun = run
        let vm = LearningViewModel(now: { clock }, makeTutor: { ProofTutorStub(lesson: self.fixtureLesson(), assessment: self.proofAssessment(outcomes: [.met, .met, .met])) })
        vm.restore([delayed, immediate])
        XCTAssertNil(map.nextDelayedReview(sessions: vm.sessions, now: clock))
        vm.setAssessmentAside(true, sessionID: delayed.id, attemptID: delayed.attempts[0].id)
        XCTAssertEqual(map.nextDelayedReview(sessions: vm.sessions, now: clock)?.previous.id, immediate.id)
        XCTAssertEqual(map.delayedEvidence(for: target, sessions: vm.sessions).first?.setAsideAt, clock)
        XCTAssertFalse(map.delayedEvidence(for: target, sessions: vm.sessions).first!.hasIndependentCorrectResult)
        XCTAssertTrue(unit.evidence(for: target, sessions: vm.sessions)!.hasIndependentCorrectResult)
        XCTAssertTrue(run.items[0].outcome!.isSetAside(in: vm.sessions))
        XCTAssertEqual(run, originalRun) // The historical grade/outcome is retained, with a live qualification.
        run.items[0].outcome = nil; run.state = .active; run.endedAt = nil
        XCTAssertFalse(run.advance(map: map, sessions: vm.sessions, at: clock))
        vm.setAssessmentAside(false, sessionID: delayed.id, attemptID: delayed.attempts[0].id)
        XCTAssertNil(map.nextDelayedReview(sessions: vm.sessions, now: clock))
        XCTAssertTrue(run.advance(map: map, sessions: vm.sessions, at: clock))
    }

    func testAssessmentReviewLegacyDecodeAndReinstatementNeverPromoteAnOriginalGrade() throws {
        let unit = try XCTUnwrap(LearningStudyPlannerService.validate(planResponse(source: source, core: [0]), source: source, corePages: [0]).first)
        for target in unit.targets {
            for grade in [LearningGrade.correct, .partial, .incorrect, .uncertain] {
                var saved = passedSession(target: target)
                let old = saved.attempts[0]
                saved.attempts[0] = .init(phase: old.phase, question: old.question, answer: old.answer,
                    assessment: .init(grade: grade, feedback: old.assessment.feedback, nextStep: old.assessment.nextStep, criteria: old.assessment.criteria),
                    assistanceUsed: false, providerID: old.providerID, modelID: old.modelID)
                var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(saved.attempts[0])) as? [String: Any])
                json.removeValue(forKey: "setAsideAt")
                let legacy = try JSONDecoder().decode(LearningAttempt.self, from: JSONSerialization.data(withJSONObject: json))
                XCTAssertNil(legacy.setAsideAt)
                XCTAssertEqual(legacy.hasIndependentCorrectResult, grade == .correct)
                let vm = LearningViewModel { ProofTutorStub(lesson: self.fixtureLesson(), assessment: self.proofAssessment(outcomes: [.met, .met, .met])) }
                vm.restore([saved])
                vm.setAssessmentAside(true, sessionID: saved.id, attemptID: saved.attempts[0].id)
                XCTAssertFalse(vm.sessions[0].passedExitCheck)
                XCTAssertEqual(vm.sessions[0].attempts[0].assessment, saved.attempts[0].assessment)
                vm.setAssessmentAside(false, sessionID: saved.id, attemptID: saved.attempts[0].id)
                XCTAssertEqual(vm.sessions[0].passedExitCheck, grade == .correct)
                XCTAssertEqual(vm.sessions[0].attempts[0], saved.attempts[0])
            }
        }
    }

    func testSetAsideCurrentFeedbackCannotUnlockExitButALaterValidAttemptCan() throws {
        for kind in LearningStudyKind.allCases {
            for phase in [LearningPhase.diagnostic, .practice] {
                let question = LearningQuestion(prompt: "Explain the inference using scalar preservation.",
                    expectedAnswer: "Apply scalar preservation at zero.", hints: [], kind: kind, gradingCriteria: proofRubric)
                var lesson = fixtureLesson(); lesson.diagnostic = question; lesson.practice = question
                let feedback = proofAssessment(outcomes: [.met, .met, .met])
                var saved = LearningSession(source: source, lesson: lesson, phase: phase, answerDraft: "My reasoning", feedback: feedback,
                    providerID: "authored", modelID: nil)
                saved.attempts = [.init(phase: phase, question: question, answer: saved.answerDraft, assessment: feedback,
                    assistanceUsed: false, providerID: "authored", modelID: nil)]
                let vm = LearningViewModel { XCTFail("Reviewing feedback must not request a tutor"); return ProofTutorStub(lesson: lesson, assessment: feedback) }
                vm.restore([saved]); vm.select(saved.id)
                XCTAssertTrue(vm.session!.feedbackSupportsProgress)
                vm.setAssessmentAside(true, sessionID: saved.id, attemptID: saved.attempts[0].id)
                XCTAssertFalse(vm.session!.feedbackSupportsProgress)
                let flagged = try XCTUnwrap(vm.session)
                vm.advance()
                XCTAssertEqual(vm.session?.phase, phase == .diagnostic ? .lesson : .practice)
                var revised = flagged
                revised.attempts.append(.init(phase: phase, question: question, answer: "A later valid revision", assessment: feedback,
                    assistanceUsed: false, providerID: "authored", modelID: nil))
                revised.answerDraft = "A later valid revision"
                vm.restore([revised]); vm.select(revised.id)
                XCTAssertTrue(vm.session!.feedbackSupportsProgress)
                vm.advance()
                XCTAssertEqual(vm.session?.phase, .exitCheck)
                XCTAssertNotNil(vm.session?.attempts.first?.setAsideAt)
                XCTAssertNil(vm.session?.attempts.last?.setAsideAt)
            }
        }
    }

    func testDelayedReviewRecordsHelpUncertaintyAndFailureWithoutReplacingImmediateEvidence() async throws {
        let unit = try XCTUnwrap(LearningStudyPlannerService.validate(planResponse(source: source, core: [0]), source: source, corePages: [0]).first)
        let target = try XCTUnwrap(unit.targets.first { $0.kind == .proof })
        let clock = Date(timeIntervalSince1970: 1_700_100_000)
        var immediate = passedSession(target: target)
        immediate.reviewDueAt = clock
        let map = LearningStudyMap(pageSignatures: [], pages: [.init(pageIndex: 0, status: .mapped)], units: [unit])
        for outcomes in [[LearningCriterionAssessment.Outcome.met, .met, .met], [.met, .uncertain, .met], [.met, .notMet, .met]] {
            let tutor = ProofTutorStub(lesson: fixtureLesson(), assessment: proofAssessment(outcomes: outcomes))
            tutor.freshQuestion = .init(prompt: "Prove the zero condition after a delay using a new representation.",
                expectedAnswer: "Use scalar preservation to derive zero preservation.", hints: [], kind: .proof, gradingCriteria: proofRubric)
            let vm = LearningViewModel(now: { clock }, makeTutor: { tutor })
            vm.restore([immediate])
            vm.startDelayedReview(try XCTUnwrap(map.nextDelayedReview(sessions: vm.sessions, now: clock)))
            await vm.waitForOperation()
            vm.openedSource()
            vm.answerDraft = "An answer with source help"
            vm.submitAnswer(); await vm.waitForOperation(); vm.advance()
            let attempt = try XCTUnwrap(vm.session?.latestExitAttempt)
            XCTAssertTrue(attempt.assistanceUsed)
            XCTAssertFalse(attempt.hasIndependentCorrectResult)
            XCTAssertEqual(vm.session?.reviewDueAt, clock.addingTimeInterval(86_400))
            XCTAssertEqual(unit.evidence(for: target, sessions: vm.sessions)?.id, immediate.attempts[0].id)
            XCTAssertEqual(map.delayedEvidence(for: target, sessions: vm.sessions).first?.id, attempt.id)
            if outcomes.contains(.uncertain) { XCTAssertEqual(attempt.assessment.grade, .uncertain) }
            if outcomes.contains(.notMet) { XCTAssertEqual(attempt.assessment.grade, .partial) }
            vm.practiseAgain()
            XCTAssertTrue(vm.session?.delayedReview?.helpUsed == true)
            XCTAssertTrue(vm.session?.assistanceUsed == true)
        }
    }

    func testDelayedReviewRejectsRepeatedQuestionsAndUnresolvedSourceBeforeCreatingWork() async throws {
        let unit = try XCTUnwrap(LearningStudyPlannerService.validate(planResponse(source: source, core: [0]), source: source, corePages: [0]).first)
        let target = unit.targets[0]
        let clock = Date(timeIntervalSince1970: 1_700_100_000)
        var immediate = passedSession(target: target)
        immediate.reviewDueAt = clock
        let map = LearningStudyMap(pageSignatures: [], pages: [.init(pageIndex: 0, status: .mapped)], units: [unit])
        let tutor = ProofTutorStub(lesson: fixtureLesson(), assessment: proofAssessment(outcomes: [.met, .met, .met]))
        let vm = LearningViewModel(now: { clock }, makeTutor: { tutor })
        vm.restore([immediate])
        let recommendation = try XCTUnwrap(map.nextDelayedReview(sessions: vm.sessions, now: clock))
        vm.startDelayedReview(recommendation); await vm.waitForOperation()
        XCTAssertEqual(vm.sessions, [immediate])
        XCTAssertNotNil(vm.errorMessage)
        var blockedMap = map
        blockedMap.units[0].pendingSourceCorrection = true
        XCTAssertNil(blockedMap.nextDelayedReview(sessions: vm.sessions, now: clock))
        vm.sourceIsCurrent = { _ in false }
        tutor.freshQuestion = .init(prompt: "Different source-based question", expectedAnswer: "A justified answer", hints: [])
        vm.startDelayedReview(recommendation); await vm.waitForOperation()
        XCTAssertEqual(vm.sessions, [immediate])
    }

    func testChapterAvailabilityTracksSourceRecoveryWithoutChangingTargetsOrEvidence() throws {
        var units = try [0, 1].map { index in
            try XCTUnwrap(LearningStudyPlannerService.validate(planResponse(source: source, core: [index]),
                source: .init(passages: [.init(pageIndex: index, text: studyText)]), corePages: [index]).first)
        }
        let old = units[0]
        units[0] = .init(id: old.id, title: old.title, anchorPage: 0, sourceQuote: old.sourceQuote,
            pageIndices: [0], prerequisites: old.prerequisites, proofRequired: true, proofQuote: nil,
            gaps: ["The proof is absent from the local excerpt."], targets: old.targets.filter { $0.kind != .proof })
        let module = LearningCourse.Module(title: "Linear consequences", goal: "Connect the results", unitIDs: units.map(\.id))
        var map = LearningStudyMap(pageSignatures: [], pages: [0, 1].map { .init(pageIndex: $0, status: .mapped) }, units: units,
            course: .init(title: "Course", overview: "Overview", modules: [module], connections: [
                .init(fromUnitID: units[0].id, toUnitID: units[1].id, reason: "Use the definition in the consequence.")]))
        let targets = map.units.map(\.targets)
        let session = passedSession(target: units[0].targets[0])
        let saved = try JSONEncoder().encode([session])
        let blocked = map.chapterAvailability(for: module)
        XCTAssertNil(blocked.request)
        XCTAssertEqual(Set(blocked.blockers.map(\.kind)), [.proof, .sourceGap])
        XCTAssertTrue(blocked.blockers.allSatisfy { $0.unitID == old.id && $0.pageIndex == 0 })
        let resolved = LearningReconciliationResponse(issues: [.init(gapIndex: 0, disposition: .foundElsewhere,
            explanation: "The full scalar argument is supplied here.", evidence: [.init(pageIndex: 0, quote: proofQuote)])],
            requestedPages: [], proofObjective: "Prove the zero-vector property using scalar preservation.",
            proofEvidence: [.init(pageIndex: 0, quote: proofQuote)])
        map.units[0].reconciliation = try LearningSourceReconciler.validate(resolved, unit: map.units[0], source: source,
            pageCount: 2, providerID: "fixture", modelID: nil)
        XCTAssertNotNil(map.chapterAvailability(for: module).request)
        XCTAssertTrue(map.chapterAvailability(for: module).blockers.isEmpty)
        XCTAssertEqual(map.units.map(\.targets), targets)
        XCTAssertEqual(map.units.map(\.id), units.map(\.id))
        XCTAssertEqual(map.units[0].checkedTargetCount(sessions: [session]), 1)
        XCTAssertNil(map.units[0].evidence(for: try XCTUnwrap(map.units[0].reconciliation?.proofTarget), sessions: [session]))
        XCTAssertEqual(try JSONDecoder().decode([LearningSession].self, from: saved), [session])
        // A newly unresolved cited page closes eligibility immediately.
        map.pages[0].status = .needsContext
        XCTAssertNil(map.chapterRequest(for: module))
        XCTAssertTrue(map.chapterAvailability(for: module).blockers.contains { $0.kind == .page && $0.pageIndex == 0 })
    }

    func testChapterAvailabilityUsesAnotherCompletePairAndExplainsMissingConnection() throws {
        let units = try [0, 1, 2].map { index in
            try XCTUnwrap(LearningStudyPlannerService.validate(planResponse(source: source, core: [index]),
                source: .init(passages: [.init(pageIndex: index, text: studyText)]), corePages: [index]).first)
        }
        let module = LearningCourse.Module(title: "Consequences", goal: "Connect the ideas", unitIDs: units.map(\.id))
        var map = LearningStudyMap(pageSignatures: [], pages: [0, 1, 2].map { .init(pageIndex: $0, status: $0 == 0 ? .needsContext : .mapped) },
            units: units, course: .init(title: "Course", overview: "Overview", modules: [module], connections: [
                .init(fromUnitID: units[0].id, toUnitID: units[1].id, reason: "First pair"),
                .init(fromUnitID: units[1].id, toUnitID: units[2].id, reason: "Second pair")]))
        XCTAssertEqual(map.chapterRequest(for: module)?.units.map(\.id), [units[1].id, units[2].id])
        map.course = .init(title: "Course", overview: "Overview", modules: [module], connections: [])
        XCTAssertNil(map.chapterRequest(for: module))
        XCTAssertEqual(map.chapterAvailability(for: module).blockers.map(\.kind), [.connection])
        // A stale module must not receive a challenge from the current course.
        XCTAssertNil(map.chapterRequest(for: .init(title: "Old", goal: "Old", unitIDs: units.map(\.id))))
    }

    func testRemappingUnchangedTopicRetainsLocatedProofTargetAndSourceEvidence() async throws {
        let pdf = try studyPDF(pages: 1)
        let source = LearningSource(passages: [.init(pageIndex: 0, text: pdf.page(at: 0)!.string!)])
        let response = planResponse(source: source, core: [0], proof: false,
                                    gaps: ["The proof is absent from the local excerpt."])
        var unit = try XCTUnwrap(LearningStudyPlannerService.validate(response, source: source, corePages: [0]).first)
        let evidence = [LearningSourceEvidence(pageIndex: 0, quote: proofQuote)]
        unit.reconciliation = try LearningSourceReconciler.validate(.init(issues: [.init(gapIndex: 0,
            disposition: .foundElsewhere, explanation: "The proof follows the statement on this source page.", evidence: evidence)],
            requestedPages: [], proofObjective: "Prove the zero-vector property by scalar preservation.", proofEvidence: evidence),
            unit: unit, source: source, pageCount: 1, providerID: "fixture", modelID: nil)
        let map = LearningStudyMap(pageSignatures: [LearningStudyInput.signature(source.passages[0].text)],
            pages: [.init(pageIndex: 0)], units: [unit])
        let planner = StudyPlannerStub()
        planner.missingProof = true
        let vm = LearningStudyMapViewModel(map: map) { planner }
        vm.build(document: pdf)
        await vm.waitForOperation()
        XCTAssertEqual(vm.map?.units[0].reconciliation, unit.reconciliation)
        XCTAssertEqual(vm.map?.units[0].learningTargets.map(\.id), unit.learningTargets.map(\.id))
        XCTAssertEqual(vm.map?.units[0].checkedTargetCount(sessions: []), 0)
    }

    func testParallelPreparationIsBoundedAndCommitsOutOfOrderWithoutLosingCoverage() async throws {
        let planner = ConcurrentStudyPlannerStub()
        let vm = LearningStudyMapViewModel { planner }
        vm.build(document: try studyPDF(pages: 10))
        for _ in 0..<1000 where planner.replies.count != 3 { await Task.yield() }
        XCTAssertEqual(Set(planner.replies.keys), [0, 3, 6])
        planner.complete(6)
        for _ in 0..<1000 where planner.replies[9] == nil { await Task.yield() }
        XCTAssertEqual(vm.processedPageCount, 3)
        XCTAssertEqual(planner.peak, 3)
        XCTAssertEqual(planner.courseCalls, 0)
        planner.complete(3)
        planner.complete(0)
        planner.complete(9)
        await vm.waitForOperation()
        XCTAssertEqual(vm.map?.resolvedPageCount, 10)
        XCTAssertEqual(vm.map?.units.map(\.anchorPage), [0, 3, 6, 9])
        XCTAssertEqual(planner.courseCalls, 1)
        XCTAssertNotNil(vm.map?.course)
    }

    func testParallelCancellationIgnoresAllLateResponses() async throws {
        let planner = ConcurrentStudyPlannerStub()
        let vm = LearningStudyMapViewModel { planner }
        vm.build(document: try studyPDF(pages: 9))
        for _ in 0..<1000 where planner.replies.count != 3 { await Task.yield() }
        XCTAssertEqual(planner.replies.count, 3)
        vm.cancel()
        for page in Array(planner.replies.keys) { planner.complete(page) }
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(vm.processedPageCount, 0)
        XCTAssertTrue(vm.map!.units.isEmpty)
        XCTAssertFalse(vm.isBusy)
        XCTAssertEqual(planner.courseCalls, 0)
    }

    func testRejectedBatchFallsBackToPagesWithoutStoppingWholeDocument() async throws {
        let planner = StudyPlannerStub()
        planner.rejectBatches = true
        let vm = LearningStudyMapViewModel { planner }
        vm.build(document: try studyPDF(pages: 4))
        await vm.waitForOperation()
        XCTAssertEqual(vm.map?.resolvedPageCount, 4)
        XCTAssertEqual(vm.processedPageCount, 4)
        XCTAssertEqual(vm.map?.units.count, 4)
        XCTAssertNotNil(vm.map?.course)
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(planner.calls, 5)
    }

    func testSlowBatchReducesScopeInsteadOfRestartingOrTimingOutEveryPage() async throws {
        let planner = StudyPlannerStub()
        planner.timeOutBatches = true
        let vm = LearningStudyMapViewModel { planner }
        vm.build(document: try studyPDF(pages: 4))
        await vm.waitForOperation()
        XCTAssertEqual(vm.map?.resolvedPageCount, 4)
        XCTAssertNotNil(vm.map?.course)
        XCTAssertEqual(planner.calls, 5)
        XCTAssertNil(vm.errorMessage)
    }

    func testStructuredProviderTimeoutPreservesWholeDocumentFallback() async throws {
        let planner = StudyPlannerStub()
        planner.timeOutBatches = true
        planner.structuredTimeout = true
        let vm = LearningStudyMapViewModel { planner }
        vm.build(document: try studyPDF(pages: 4))
        await vm.waitForOperation()
        XCTAssertEqual(vm.map?.resolvedPageCount, 4)
        XCTAssertNotNil(vm.map?.course)
        XCTAssertEqual(planner.calls, 5)
        XCTAssertNil(vm.errorMessage)
    }

    func testRetryReceivesTheValidationProblemAndPreservesWholeDocumentCoverage() async throws {
        let planner = StudyPlannerStub()
        planner.needsRepair = true
        let vm = LearningStudyMapViewModel { planner }
        vm.build(document: try studyPDF(pages: 3))
        await vm.waitForOperation()
        XCTAssertEqual(vm.map?.resolvedPageCount, 3)
        XCTAssertNotNil(vm.map?.course)
        XCTAssertEqual(planner.repairNotes.count, 3)
        XCTAssertTrue(planner.repairNotes.allSatisfy { $0.contains("proof quote") })
        XCTAssertNil(vm.errorMessage)
    }

    func testPermanentlyRejectedPageStaysOpenWhileRemainingPagesComplete() async throws {
        let planner = StudyPlannerStub()
        planner.rejectedPages = [1]
        let vm = LearningStudyMapViewModel { planner }
        vm.build(document: try studyPDF(pages: 4))
        await vm.waitForOperation()
        XCTAssertEqual(vm.processedPageCount, 4)
        XCTAssertEqual(vm.map?.resolvedPageCount, 3)
        XCTAssertEqual(vm.map?.pages[1].status, .needsContext)
        XCTAssertEqual(vm.map?.units.count, 3)
        XCTAssertNotNil(vm.map?.course)
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(planner.calls, 6)
        XCTAssertFalse(vm.map!.units.contains { $0.anchorPage == 1 })
    }

    private func courseUnits(count: Int, repetitions: Int) -> [LearningStudyUnit] {
        (0..<count).map { index in
            let id = UUID()
            return .init(id: id, title: "Topic \(index + 1)", anchorPage: index, sourceQuote: studyQuote,
                pageIndices: [index], prerequisites: ["Vector space definitions"], proofRequired: false,
                proofQuote: nil, gaps: ["A prerequisite proof is absent from the supplied notes."],
                targets: [.concept, .application].map { kind in
                    .init(unitID: id, kind: kind, objective: String(repeating: "Explain the hypotheses and justify the conclusion. ", count: repetitions))
                })
        }
    }

    func testLargeInventoryIsGloballyComposedWithoutDroppingAnyTopicOrChangingGaps() async throws {
        struct Item: Decodable { let unitNumbers: [Int] }
        let units = courseUnits(count: 8, repetitions: 16)
        let original = units
        var inputs: [[Int]] = []
        let course = try await LearningCourseComposer.build(units: units, capacity: 2_400) { input in
            XCTAssertLessThanOrEqual(input.count, 2_400)
            let numbers = try JSONDecoder().decode([Item].self, from: Data(input.utf8)).flatMap(\.unitNumbers)
            inputs.append(numbers)
            return .init(title: "Connected notes", overview: "Connect the foundations and applications.",
                modules: [.init(title: "Ideas together", goal: "Apply the definitions with justification.", unitNumbers: numbers)],
                connections: numbers.count == units.count ? [.init(from: 1, to: 8, reason: "Use the first topic in the last application.")] : [])
        }
        XCTAssertGreaterThan(inputs.count, 1)
        XCTAssertLessThan(inputs.first!.count, units.count)
        XCTAssertEqual(inputs.last, Array(1...8), "The final pass must see every regional topic together.")
        XCTAssertEqual(course.modules.flatMap(\.unitIDs), units.map(\.id))
        XCTAssertEqual(course.connections.count, 1)
        XCTAssertEqual(units, original, "Organization must not rewrite or close original source gaps.")
    }

    func testGlobalReorderingCannotContradictARegionalDependency() async throws {
        struct Item: Decodable { let unitNumbers: [Int] }
        let units = courseUnits(count: 8, repetitions: 4)
        var recordedDependency = false
        do {
            _ = try await LearningCourseComposer.build(units: units, capacity: 2_400) { input in
                let numbers = try JSONDecoder().decode([Item].self, from: Data(input.utf8)).flatMap(\.unitNumbers)
                let global = numbers.count == units.count
                let connections: [LearningCourseResponse.Connection]
                if !global && numbers.count > 1 {
                    recordedDependency = true
                    connections = [.init(from: numbers.first!, to: numbers.last!, reason: "The first idea supports the later proof.")]
                } else { connections = [] }
                return .init(title: "Connected notes", overview: "Relate the ideas.",
                    modules: [.init(title: "Ideas together", goal: "Justify the connections.", unitNumbers: global ? numbers.reversed() : numbers)],
                    connections: connections)
            }
            XCTFail("A global order that reverses the retained dependency must be rejected.")
        } catch LearningError.invalidCourse {
            XCTAssertTrue(recordedDependency)
        }
    }

    func testWholeCourseCannotDropDuplicateOrInventTopicsOrReverseDependencies() throws {
        let first = try XCTUnwrap(LearningStudyPlannerService.validate(planResponse(source: source, core: [0]), source: source, corePages: [0]).first)
        let laterSource = LearningSource(passages: [.init(pageIndex: 3, text: studyText)])
        let second = try XCTUnwrap(LearningStudyPlannerService.validate(planResponse(source: laterSource, core: [3]), source: laterSource, corePages: [3]).first)
        let units = [first, second]
        func response(_ numbers: [Int], from: Int = 2, to: Int = 1) -> LearningCourseResponse {
            .init(title: "A connected course", overview: "Foundations support the later argument.",
                modules: [.init(title: "Foundations and consequences", goal: "Connect the ideas.", unitNumbers: numbers)],
                connections: [.init(from: from, to: to, reason: "Apply the definition in the proof.")])
        }
        let course = try LearningStudyPlannerService.validateCourse(response([2, 1]), units: units)
        XCTAssertEqual(course.modules[0].unitIDs, [second.id, first.id])
        XCTAssertEqual(course.connections[0].fromUnitID, second.id)
        for numbers in [[1], [1, 1], [1, 3]] {
            XCTAssertThrowsError(try LearningStudyPlannerService.validateCourse(response(numbers), units: units))
        }
        XCTAssertThrowsError(try LearningStudyPlannerService.validateCourse(response([2, 1], from: 1, to: 2), units: units))
        XCTAssertThrowsError(try LearningStudyPlannerService.validateCourse(response([2, 1], from: 2, to: 2), units: units))
        let map = LearningStudyMap(pageSignatures: [], pages: [], units: units, course: course)
        XCTAssertEqual(map.nextStudy(sessions: [])?.unit.id, second.id)
        let loaded = try JSONDecoder().decode(LearningStudyMap.self, from: JSONEncoder().encode(map))
        XCTAssertEqual(loaded.course, course)
    }

    func testWholeDocumentPreparationResumesAfterGlobalPlanningFailure() async throws {
        let planner = StudyPlannerStub()
        planner.failCourse = true
        let vm = LearningStudyMapViewModel { planner }
        let document = try studyPDF(pages: 6)
        vm.build(document: document)
        await vm.waitForOperation()
        XCTAssertEqual(vm.map?.resolvedPageCount, 6)
        XCTAssertEqual(planner.calls, 2)
        XCTAssertEqual(planner.courseCalls, 1)
        XCTAssertNil(vm.map?.course)
        XCTAssertNotNil(vm.errorMessage)
        let ids = vm.map!.units.flatMap(\.targets).map(\.id)
        planner.failCourse = false
        vm.build(document: document)
        await vm.waitForOperation()
        XCTAssertEqual(planner.calls, 2, "Retry must use the complete saved inventory rather than remapping it.")
        XCTAssertEqual(planner.courseCalls, 2)
        XCTAssertEqual(vm.map?.units.flatMap(\.targets).map(\.id), ids)
        XCTAssertEqual(vm.map?.course?.modules.flatMap(\.unitIDs), vm.map?.units.map(\.id))
        XCTAssertEqual(vm.map?.course?.connections.count, 1)
        XCTAssertNil(vm.errorMessage)
    }

    func testCancellingGlobalPlanningIgnoresLateCourseWithoutLosingInventory() async throws {
        let planner = StudyPlannerStub()
        planner.delayCourse = true
        let vm = LearningStudyMapViewModel { planner }
        vm.build(document: try studyPDF(pages: 4))
        for _ in 0..<1000 where planner.courseContinuation == nil { await Task.yield() }
        let continuation = try XCTUnwrap(planner.courseContinuation)
        XCTAssertTrue(vm.isConnectingTopics)
        XCTAssertEqual(vm.map?.resolvedPageCount, 4)
        vm.cancel()
        continuation.resume(returning: try XCTUnwrap(planner.delayedCourse))
        await Task.yield()
        XCTAssertFalse(vm.isBusy)
        XCTAssertFalse(vm.isConnectingTopics)
        XCTAssertNil(vm.map?.course)
        XCTAssertEqual(vm.map?.units.count, 2)
    }

    func testNextLessonResumesOpenRequirementAndNeverSkipsAnAssistedProof() throws {
        let unit = try XCTUnwrap(LearningStudyPlannerService.validate(planResponse(source: source, core: [0]), source: source, corePages: [0]).first)
        let map = LearningStudyMap(pageSignatures: [LearningStudyInput.signature(studyText)], pages: [.init(pageIndex: 0, status: .mapped)], units: [unit])
        XCTAssertEqual(map.nextStudy(sessions: [])?.target.id, unit.targets[0].id)
        let concept = passedSession(target: unit.targets[0])
        XCTAssertEqual(map.nextStudy(sessions: [concept])?.target.kind, .proof)
        var proof = passedSession(target: unit.targets[1], help: true)
        proof.updatedAt = Date(timeIntervalSince1970: 200)
        var application = passedSession(target: unit.targets[2])
        application.phase = .practice
        application.attempts = []
        application.updatedAt = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(map.nextStudy(sessions: [concept, application, proof])?.session?.id, proof.id)
        proof = passedSession(target: unit.targets[1])
        XCTAssertEqual(map.nextStudy(sessions: [concept, proof, application])?.session?.id, application.id)
        XCTAssertNil(map.nextStudy(sessions: unit.targets.map { passedSession(target: $0) }))
        let unrelated = passedSession(target: .init(unitID: UUID(), kind: .proof, objective: "An unrelated argument"))
        XCTAssertEqual(map.nextStudy(sessions: [unrelated])?.target.id, unit.targets[0].id)
    }

    private func sourceBlockedUnit() throws -> LearningStudyUnit {
        try XCTUnwrap(LearningStudyPlannerService.validate(planResponse(source: source, core: [0],
            gaps: ["The extracted formula may lack a radical; verify the original typesetting."]), source: source, corePages: [0]).first)
    }

    func testBlockedNextRequirementOffersSourceReviewWithoutAnAssistantOrSkippingAhead() throws {
        let blocked = try sourceBlockedUnit()
        let other = try XCTUnwrap(LearningStudyPlannerService.validate(planResponse(source: source, core: [0]),
            source: source, corePages: [0]).first)
        let map = LearningStudyMap(pageSignatures: [], pages: [], units: [blocked, other])
        let next = try XCTUnwrap(map.nextStudy(sessions: []))
        XCTAssertEqual(next.unit.id, blocked.id)
        XCTAssertTrue(next.requiresSourceReview)
        XCTAssertEqual(next.actionLabel, "Review source")
        XCTAssertTrue(next.canPerformAction(assistantAvailable: false, isBusy: false))
        XCTAssertFalse(next.canPerformAction(assistantAvailable: true, isBusy: true))
        XCTAssertEqual(next.sourceReviewPageIndex, blocked.anchorPage)
        XCTAssertEqual(map.nextStudy(sessions: [])?.target.id, blocked.targets[0].id)
    }

    func testOtherWorkIsAnExplicitChoiceAndCannotWaiveBlockedSourceOrProofObligations() throws {
        let blocked = try sourceBlockedUnit()
        let other = try XCTUnwrap(LearningStudyPlannerService.validate(planResponse(source: source, core: [0]),
            source: source, corePages: [0]).first)
        let map = LearningStudyMap(pageSignatures: [], pages: [], units: [blocked, other])
        let original = map
        let choices = map.availableStudyChoices(sessions: [])
        XCTAssertEqual(choices.map(\.target.id), other.targets.map(\.id))
        XCTAssertTrue(choices.allSatisfy { !$0.requiresSourceReview })
        XCTAssertEqual(choices[0].unit.prerequisites, other.prerequisites)
        XCTAssertEqual(map.nextStudy(sessions: [])?.unit.id, blocked.id)
        XCTAssertTrue(blocked.proofRequired)
        XCTAssertEqual(blocked.openGapCount, 1)
        XCTAssertFalse(blocked.hasEvidenceForEveryTarget(sessions: blocked.targets.map { passedSession(target: $0) }))
        XCTAssertEqual(map, original)
    }

    func testSavedBlockedLessonAndItsAssistedEvidenceRemainAccessibleOffline() throws {
        let unit = try sourceBlockedUnit()
        var session = passedSession(target: unit.targets[1], help: true)
        session.answerDraft = "Keep this proof draft."
        let original = session
        let map = LearningStudyMap(pageSignatures: [], pages: [], units: [unit])
        let next = try XCTUnwrap(map.nextStudy(sessions: [session]))
        XCTAssertEqual(next.session?.id, session.id)
        XCTAssertFalse(next.requiresSourceReview)
        XCTAssertEqual(next.actionLabel, "Continue lesson")
        XCTAssertTrue(next.canPerformAction(assistantAvailable: false, isBusy: false))
        XCTAssertEqual(map.availableStudyChoices(sessions: [session]).map(\.target.id), [unit.targets[1].id])
        XCTAssertEqual(next.session, original)
        XCTAssertEqual(unit.openGapCount, 1)
        XCTAssertFalse(unit.hasEvidenceForEveryTarget(sessions: [session]))
    }

    func testOnlyBlockedWorkStillHasAnEnabledReviewActionAndRetainsAllTargets() throws {
        let unit = try sourceBlockedUnit()
        let map = LearningStudyMap(pageSignatures: [], pages: [], units: [unit])
        XCTAssertTrue(map.availableStudyChoices(sessions: []).isEmpty)
        let next = try XCTUnwrap(map.nextStudy(sessions: []))
        XCTAssertTrue(next.canPerformAction(assistantAvailable: false, isBusy: false))
        XCTAssertEqual(next.unit.learningTargets.map(\.id), unit.targets.map(\.id))
        XCTAssertEqual(next.unit.gaps, unit.gaps)
        XCTAssertEqual(next.unit.checkedTargetCount(sessions: []), 0)
    }

    func testSourceReviewOpensTheCitedFaultPageWithoutChangingSavedLearnerEvidence() throws {
        var unit = try sourceBlockedUnit()
        let source = LearningSource(passages: [.init(pageIndex: 0, text: studyText), .init(pageIndex: 1, text: studyText)])
        unit.reconciliation = try LearningSourceReconciler.validate(.init(issues: [.init(gapIndex: 0,
            disposition: .extractionProblem, explanation: "Inspect the mathematical notation on the cited original page.",
            evidence: [.init(pageIndex: 1, quote: proofQuote)])], requestedPages: [], proofObjective: nil, proofEvidence: []),
            unit: unit, source: source, pageCount: 2, providerID: "fixture", modelID: nil)
        let session = passedSession(target: unit.targets[1], help: true)
        let map = LearningStudyMap(pageSignatures: [], pages: [], units: [unit])
        let document = LearningDocument(workspace: .init(documentURL: URL(fileURLWithPath: "/tmp/source-review.pdf"),
            learningSessions: [session], learningStudyMap: map), document: try studyPDF(pages: 2), bookmarkData: nil)
        let next = try XCTUnwrap(map.nextStudy(sessions: []))
        document.showNotes(at: next.sourceReviewPageIndex)
        XCTAssertTrue(document.notesVisible)
        XCTAssertEqual(document.notesPageIndex, 1)
        XCTAssertEqual(document.learning.sessions, [session])
        XCTAssertEqual(document.studyMap.map, map)
        XCTAssertTrue(document.studyMap.map!.units[0].needsSourceReview)
    }

    func testMissingPageCannotCountAsSourceCoverage() {
        let response = planResponse(source: source, core: [0])
        let twoPages = LearningSource(passages: source.passages + [.init(pageIndex: 1, text: studyText)])
        XCTAssertThrowsError(try LearningStudyPlannerService.validate(response, source: twoPages, corePages: [0, 1]))
    }

    func testInventedProofQuoteAndUnaccountedProofAreRejected() {
        let good = planResponse(source: source, core: [0])
        let original = good.units[0]
        let invented = LearningStudyPlanResponse.Unit(title: original.title, anchorPage: 1, sourceQuote: studyQuote,
            pageNumbers: [1], prerequisites: [], proofRequired: true, proofQuote: "A proof that is nowhere in the uploaded notes.", gaps: [], targets: original.targets)
        XCTAssertThrowsError(try LearningStudyPlannerService.validate(.init(units: [invented], pages: good.pages), source: source, corePages: [0]))
        XCTAssertThrowsError(try LearningStudyPlannerService.validate(planResponse(source: source, core: [0], proof: false), source: source, corePages: [0]))
        XCTAssertNoThrow(try LearningStudyPlannerService.validate(planResponse(source: source, core: [0], proof: false, gaps: ["The proof needs more context."]), source: source, corePages: [0]))
    }

    func testInstructionalPageCannotBeExcludedAsAdministrative() {
        let excluded = LearningStudyPlanResponse(units: [], pages: [.init(pageNumber: 1, status: .nonInstructional, reason: "Administrative.", sourceQuote: studyQuote)])
        XCTAssertThrowsError(try LearningStudyPlannerService.validate(excluded, source: source, corePages: [0]))
    }

    func testApplicationEvidenceDoesNotSatisfyProofRequirement() throws {
        let unit = try XCTUnwrap(LearningStudyPlannerService.validate(planResponse(source: source, core: [0]), source: source, corePages: [0]).first)
        let sessions = unit.targets.filter { $0.kind != .proof }.map { passedSession(target: $0) }
        XCTAssertEqual(unit.checkedTargetCount(sessions: sessions), 2)
        XCTAssertFalse(unit.hasEvidenceForEveryTarget(sessions: sessions))
        let all = sessions + [passedSession(target: unit.targets.first { $0.kind == .proof }!)]
        XCTAssertTrue(unit.hasEvidenceForEveryTarget(sessions: all))
    }

    func testAssistedOrUnvalidatedProofDoesNotCloseRequirement() throws {
        let unit = try XCTUnwrap(LearningStudyPlannerService.validate(planResponse(source: source, core: [0]), source: source, corePages: [0]).first)
        let target = try XCTUnwrap(unit.targets.first { $0.kind == .proof })
        XCTAssertEqual(unit.checkedTargetCount(sessions: [passedSession(target: target, help: true)]), 0)
        var unvalidated = passedSession(target: target)
        unvalidated.attempts[0] = .init(phase: .exitCheck, question: unvalidated.lesson.exitCheck, answer: "An assertion",
            assessment: .init(grade: .correct, feedback: "Correct", nextStep: "Continue"), assistanceUsed: false, providerID: "fixture", modelID: nil)
        XCTAssertEqual(unit.checkedTargetCount(sessions: [unvalidated]), 0)
        XCTAssertFalse(unvalidated.passedExitCheck)
        XCTAssertEqual(unvalidated.progressLabel, "Proof assessment incomplete")
    }

    func testMissingSourceProofRemainsGapEvenWhenAvailableChecksPass() throws {
        let unit = try XCTUnwrap(LearningStudyPlannerService.validate(planResponse(source: source, core: [0], proof: false,
            gaps: ["Proof omitted in the notes."]), source: source, corePages: [0]).first)
        let sessions = unit.targets.map { passedSession(target: $0) }
        XCTAssertEqual(unit.checkedTargetCount(sessions: sessions), unit.targets.count)
        XCTAssertFalse(unit.hasEvidenceForEveryTarget(sessions: sessions))
    }

    func testProofWithMissingEssentialCriterionCannotReceiveCorrect() throws {
        let question = proofQuestion()
        let inconsistent = proofAssessment(outcomes: [.met, .notMet, .met])
        XCTAssertEqual(try LearningTutorService.checkedAssessment(inconsistent, question: question).grade, .partial)
        XCTAssertEqual(try LearningTutorService.checkedAssessment(proofAssessment(outcomes: [.met, .uncertain, .met]), question: question).grade, .uncertain)
        XCTAssertEqual(try LearningTutorService.checkedAssessment(proofAssessment(outcomes: [.met, .met, .met]), question: question).grade, .correct)
    }

    func testCriteriaConsistencyAppliesToEveryQuestionKindWithoutPromotingGrades() throws {
        for kind in LearningStudyKind.allCases {
            var question = proofQuestion(); question.kind = kind
            XCTAssertEqual(try LearningTutorService.checkedAssessment(proofAssessment(outcomes: [.met, .notMet, .met]), question: question).grade, .partial)
            XCTAssertEqual(try LearningTutorService.checkedAssessment(proofAssessment(outcomes: [.met, .uncertain, .met]), question: question).grade, .uncertain)
            for grade in [LearningGrade.partial, .incorrect, .uncertain] {
                let original = LearningAssessment(grade: grade, feedback: "Keep this judgement", nextStep: "Review the original gap",
                    criteria: proofAssessment(outcomes: [.met, .met, .met]).criteria)
                XCTAssertEqual(try LearningTutorService.checkedAssessment(original, question: question).grade, grade)
            }
        }
        let holistic = LearningQuestion(prompt: "Explain a concept", expectedAnswer: "A valid explanation", hints: [], kind: .concept)
        XCTAssertEqual(try LearningTutorService.checkedAssessment(.init(grade: .correct, feedback: "A specific valid step", nextStep: "Try another case"), question: holistic).grade, .correct)
        XCTAssertEqual(try LearningTutorService.checkedAssessment(proofAssessment(outcomes: [.uncertain]), question: holistic).grade, .uncertain)
        var short = holistic; short.gradingCriteria = ["Justify the inference"]
        XCTAssertNoThrow(try LearningTutorService.checkedAssessment(proofAssessment(outcomes: [.met]), question: short))
        short.kind = .proof
        XCTAssertThrowsError(try LearningTutorService.checkedAssessment(proofAssessment(outcomes: [.met]), question: short))
    }

    func testSuppliedNonProofRubricsRequireCompleteUniqueUsableCriteria() {
        for kind in [LearningStudyKind.concept, .application] {
            var question = proofQuestion(); question.kind = kind
            let invalid = [
                LearningAssessment(grade: .correct, feedback: "Specific feedback", nextStep: "Review"),
                proofAssessment(outcomes: [.met, .met]),
                LearningAssessment(grade: .correct, feedback: "Specific feedback", nextStep: "Review",
                    criteria: [0, 0, 2].map { .init(index: $0, outcome: .met, feedback: "Specific criterion") }),
                LearningAssessment(grade: .correct, feedback: "Specific feedback", nextStep: "Review",
                    criteria: [0, 1, 99].map { .init(index: $0, outcome: .met, feedback: "Specific criterion") }),
                LearningAssessment(grade: .correct, feedback: "Specific feedback", nextStep: "Review",
                    criteria: [0, 1, 2].map { .init(index: $0, outcome: .met, feedback: " ") })
            ]
            for assessment in invalid { XCTAssertThrowsError(try LearningTutorService.checkedAssessment(assessment, question: question)) }
            question.gradingCriteria = ["", "Reason", "Conclude"]
            XCTAssertThrowsError(try LearningTutorService.checkedAssessment(proofAssessment(outcomes: [.met, .met, .met]), question: question))
        }
    }

    func testContradictorySavedConceptAndApplicationEvidenceRemainsIntactButOpen() throws {
        let unit = try XCTUnwrap(LearningStudyPlannerService.validate(planResponse(source: source, core: [0]), source: source, corePages: [0]).first)
        for target in unit.targets where target.kind != .proof {
            var saved = passedSession(target: target)
            saved.attempts = [.init(phase: .exitCheck, question: saved.attempts[0].question, answer: "Retain this exact old reasoning",
                assessment: proofAssessment(outcomes: [.met, .notMet, .met]), assistanceUsed: false, providerID: "legacy", modelID: nil)]
            let original = saved
            XCTAssertFalse(saved.passedExitCheck)
            XCTAssertEqual(saved.progressLabel, "Assessment needs checking")
            XCTAssertEqual(unit.checkedTargetCount(sessions: [saved]), 0)
            XCTAssertEqual(unit.evidence(for: target, sessions: [saved])?.assessment.grade, .correct)
            let entry = try XCTUnwrap(LearningRequirementHistory.entries(for: target, in: [saved]).first)
            XCTAssertEqual(entry.status, "Assessment needs checking")
            XCTAssertTrue(entry.incompleteCriteriaAssessment)
            XCTAssertEqual(entry.assessment?.grade, .correct)
            XCTAssertEqual(saved, original)
            let restored = try JSONDecoder().decode(LearningSession.self, from: JSONEncoder().encode(saved))
            XCTAssertFalse(restored.passedExitCheck)
            XCTAssertEqual(restored.attempts[0].answer, original.attempts[0].answer)
            XCTAssertEqual(restored.attempts[0].assessment, original.attempts[0].assessment)
            var practice = restored
            practice.phase = .practice
            practice.lesson.practice = restored.attempts[0].question
            practice.feedback = restored.attempts[0].assessment
            let vm = LearningViewModel { ProofTutorStub(lesson: practice.lesson, assessment: practice.feedback!) }
            vm.restore([practice]); vm.select(practice.id); vm.advance()
            XCTAssertEqual(vm.session, practice) // A saved optimistic grade cannot bypass the gate on resume.
        }
    }

    func testConceptAndApplicationPracticeCriteriaCannotUnlockExitOnAnOptimisticGrade() async {
        for kind in [LearningStudyKind.concept, .application] {
            for outcome in [LearningCriterionAssessment.Outcome.notMet, .uncertain] {
                let tutor = ProofTutorStub(lesson: fixtureLesson(), assessment: proofAssessment(outcomes: [.met, outcome, .met]))
                let vm = LearningViewModel { tutor }
                vm.start(source: source, target: .init(unitID: UUID(), kind: kind, objective: "Explain the zero condition"))
                await vm.waitForOperation()
                vm.studyInstead(); vm.advance()
                vm.answerDraft = "A partly justified argument"
                vm.submitAnswer(); await vm.waitForOperation(); vm.advance()
                XCTAssertEqual(vm.session?.phase, .practice)
                XCTAssertEqual(vm.session?.feedback?.grade, outcome == .uncertain ? .uncertain : .partial)
                XCTAssertEqual(vm.session?.attempts.count, 1)
                XCTAssertFalse(vm.session?.attempts[0].hasIndependentCorrectResult == true)
                XCTAssertNil(vm.session?.reviewDueAt)
            }
        }
    }

    func testContradictoryDelayedCriteriaCannotAdvanceAPlanOrEarnSuccessfulReviewSpacing() async throws {
        let unit = try XCTUnwrap(LearningStudyPlannerService.validate(planResponse(source: source, core: [0]), source: source, corePages: [0]).first)
        let clock = Date(timeIntervalSince1970: 1_700_100_000)
        for target in unit.targets where target.kind != .proof {
            for outcome in [LearningCriterionAssessment.Outcome.notMet, .uncertain] {
                var immediate = passedSession(target: target); immediate.reviewDueAt = clock
                let map = LearningStudyMap(pageSignatures: [], pages: [.init(pageIndex: 0, status: .mapped)], units: [unit])
                let tutor = ProofTutorStub(lesson: fixtureLesson(), assessment: proofAssessment(outcomes: [.met, outcome, .met]))
                tutor.freshQuestion = .init(prompt: "Revisit the zero condition using a different representation.",
                    expectedAnswer: "Use scalar preservation with zero.", hints: [], kind: target.kind, gradingCriteria: proofRubric)
                let vm = LearningViewModel(now: { clock }, makeTutor: { tutor })
                vm.restore([immediate])
                vm.startDelayedReview(try XCTUnwrap(map.nextDelayedReview(sessions: vm.sessions, now: clock)))
                await vm.waitForOperation()
                vm.answerDraft = "An incomplete delayed argument"
                vm.submitAnswer(); await vm.waitForOperation(); vm.advance()
                let result = try XCTUnwrap(vm.session)
                XCTAssertFalse(result.passedExitCheck)
                XCTAssertEqual(result.reviewDueAt, clock.addingTimeInterval(86_400))
                XCTAssertEqual(result.latestExitAttempt?.assessment.grade, outcome == .uncertain ? .uncertain : .partial)
                var run = LearningStudyRun(pageSignatures: map.pageSignatures,
                    items: [.init(unitID: unit.id, title: unit.title, target: target, mode: .delayedReview,
                        existingSessionID: result.id, earlierAttemptIDs: [])], startedAt: clock)
                XCTAssertFalse(run.advance(map: map, sessions: vm.sessions, at: clock))
                XCTAssertEqual(run.attemptedCount, 0)
                XCTAssertEqual(vm.sessions.first { $0.id == immediate.id }, immediate)
            }
        }
    }

    func testFailedProofEvidenceRemainsVisibleWithoutClosingRequirement() throws {
        let unit = try XCTUnwrap(LearningStudyPlannerService.validate(planResponse(source: source, core: [0]), source: source, corePages: [0]).first)
        let target = try XCTUnwrap(unit.targets.first { $0.kind == .proof })
        var session = passedSession(target: target)
        let feedback = try LearningTutorService.checkedAssessment(proofAssessment(outcomes: [.met, .notMet, .met]), question: session.lesson.exitCheck)
        session.attempts = [.init(phase: .exitCheck, question: session.lesson.exitCheck, answer: "A missing justification",
            assessment: feedback, assistanceUsed: false, providerID: "fixture", modelID: nil)]
        XCTAssertEqual(unit.evidence(for: target, sessions: [session])?.assessment.grade, .partial)
        XCTAssertEqual(unit.checkedTargetCount(sessions: [session]), 0)
    }

    func testProofAssessmentGateAppliesInTheLiveLearningStateMachine() async {
        var lesson = fixtureLesson()
        lesson.proof = fixtureProof()
        let tutor = ProofTutorStub(lesson: lesson, assessment: proofAssessment(outcomes: [.met, .notMet, .met]))
        let vm = LearningViewModel { tutor }
        let target = LearningStudyTarget(unitID: UUID(), kind: .proof, objective: "Prove the zero-vector condition.")
        vm.start(source: source, target: target)
        await vm.waitForOperation()
        XCTAssertEqual(vm.session?.studyTarget, target)
        vm.studyInstead()
        vm.advance()
        vm.answerDraft = "The conclusion alone."
        vm.submitAnswer()
        await vm.waitForOperation()
        XCTAssertEqual(vm.session?.feedback?.grade, .partial)
        vm.advance()
        XCTAssertEqual(vm.session?.phase, .practice)
        vm.tryAgain()
        tutor.assessment = proofAssessment(outcomes: [.met, .met, .met])
        vm.answerDraft = "A complete justified proof."
        vm.submitAnswer()
        await vm.waitForOperation()
        vm.advance()
        XCTAssertEqual(vm.session?.phase, .exitCheck)
    }

    func testMissingOrDuplicatedProofCriteriaAreRejected() {
        let missing = LearningAssessment(grade: .correct, feedback: "Looks correct", nextStep: "Continue")
        XCTAssertThrowsError(try LearningTutorService.checkedAssessment(missing, question: proofQuestion()))
        let duplicate = LearningAssessment(grade: .correct, feedback: "Looks correct", nextStep: "Continue",
            criteria: [0, 0, 2].map { .init(index: $0, outcome: .met, feedback: "A justified step.") })
        XCTAssertThrowsError(try LearningTutorService.checkedAssessment(duplicate, question: proofQuestion()))
    }

    func testProofTargetRejectsApplicationOnlyLessonAndUnjustifiedSteps() {
        let target = LearningStudyTarget(unitID: UUID(), kind: .proof, objective: "Prove that a linear map sends zero to zero.")
        let lesson = fixtureLesson()
        XCTAssertThrowsError(try LearningTutorService.validate(lesson, source: source, target: target))
        var valid = lesson
        valid.proof = fixtureProof()
        XCTAssertNoThrow(try LearningTutorService.validate(valid, source: source, target: target))
        valid.proof = .init(statement: "T(0)=0", assumptions: [], strategy: "Use an example", steps: [], conclusion: "Done", sourceQuote: proofQuote)
        XCTAssertThrowsError(try LearningTutorService.validate(valid, source: source, target: target))
    }

    func testChunkingKeepsNeighbourContextAndNeverTruncatesLongPages() {
        let pages = [studyText, studyText, studyText]
        let source = LearningStudyInput.source(pages: pages, core: [1], limit: 14_000)
        XCTAssertEqual(source?.passages.map(\.pageIndex), [0, 1, 2])
        XCTAssertEqual(source?.passages[1].text, studyText)
        XCTAssertNil(LearningStudyInput.source(pages: [String(repeating: "proof ", count: 1000)], core: [0], limit: 2_400))
    }

    func testMappingFailureRetainsEarlierBatchesAndResumesWithoutDuplicates() async throws {
        let document = try studyPDF(pages: 4)
        let planner = StudyPlannerStub()
        planner.failCall = 2
        let vm = LearningStudyMapViewModel { planner }
        vm.build(document: document)
        await vm.waitForOperation()
        XCTAssertEqual(vm.map?.resolvedPageCount, 3)
        XCTAssertNotNil(vm.errorMessage)
        let firstIDs = vm.map!.units[0].targets.map(\.id)
        planner.failCall = nil
        vm.build(document: document)
        await vm.waitForOperation()
        XCTAssertEqual(vm.map?.resolvedPageCount, 4)
        XCTAssertEqual(vm.map?.units.count, 2)
        XCTAssertEqual(vm.map?.units[0].targets.map(\.id), firstIDs)
        XCTAssertNil(vm.errorMessage)
    }

    func testCancellationIgnoresLatePlannerResponse() async throws {
        let planner = StudyPlannerStub()
        planner.delay = true
        let vm = LearningStudyMapViewModel { planner }
        vm.build(document: try studyPDF(pages: 1))
        for _ in 0..<1000 where planner.continuation == nil { await Task.yield() }
        let continuation = try XCTUnwrap(planner.continuation)
        vm.cancel()
        continuation.resume(returning: try XCTUnwrap(planner.delayedResponse))
        await Task.yield()
        XCTAssertFalse(vm.isBusy)
        XCTAssertEqual(vm.map?.resolvedPageCount, 0)
        XCTAssertTrue(vm.map?.units.isEmpty == true)
    }

    func testSourceChangeRebuildsRequirementsWithoutReusingOldEvidence() async throws {
        let planner = StudyPlannerStub()
        let vm = LearningStudyMapViewModel { planner }
        vm.build(document: try studyPDF(pages: 1))
        await vm.waitForOperation()
        let oldTarget = try XCTUnwrap(vm.map?.units.first?.targets.first)
        let oldSession = passedSession(target: oldTarget)
        vm.build(document: try studyPDF(pages: 1, extra: "\nAn additional source condition that changes the document."))
        await vm.waitForOperation()
        let newUnit = try XCTUnwrap(vm.map?.units.first)
        XCTAssertFalse(newUnit.targets.contains { $0.id == oldTarget.id })
        XCTAssertEqual(newUnit.checkedTargetCount(sessions: [oldSession]), 0)
    }

    func testOversizedAndUnreadablePagesRemainUnresolved() async throws {
        let planner = StudyPlannerStub()
        planner.sourceLimit = 50
        let vm = LearningStudyMapViewModel { planner }
        vm.build(document: try studyPDF(pages: 1))
        await vm.waitForOperation()
        XCTAssertEqual(vm.map?.pages.first?.status, .tooLong)
        XCTAssertEqual(planner.calls, 0)
        let imageOnly = PDFDocument()
        imageOnly.insert(PDFPage(image: NSImage(size: .init(width: 100, height: 100), flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(rect: CGRect(x: 20, y: 20, width: 60, height: 60)).fill()
            return true
        })!, at: 0)
        vm.build(document: imageOnly)
        await vm.waitForOperation()
        XCTAssertEqual(vm.map?.pages.first?.status, .unreadable)
        XCTAssertEqual(vm.map?.resolvedPageCount, 0)
    }

    func testBlankPageIsAccountedForButVisibleScanOrAnnotationCannotBeExcluded() async throws {
        let blank = try XCTUnwrap(PDFPage(image: NSImage(size: .init(width: 100, height: 100), flipped: false) { _ in true }))
        XCTAssertTrue(LearningStudyInput.isBlank(blank))
        let document = PDFDocument()
        document.insert(blank, at: 0)
        let planner = StudyPlannerStub()
        let vm = LearningStudyMapViewModel { planner }
        vm.build(document: document)
        await vm.waitForOperation()
        XCTAssertEqual(vm.processedPageCount, 1)
        XCTAssertEqual(vm.map?.pages[0].status, .nonInstructional)
        XCTAssertEqual(planner.calls, 0)
        blank.addAnnotation(PDFAnnotation(bounds: CGRect(x: 10, y: 10, width: 60, height: 60), forType: .ink, withProperties: nil))
        XCTAssertFalse(LearningStudyInput.isBlank(blank))
        let visible = try XCTUnwrap(PDFPage(image: NSImage(size: .init(width: 100, height: 100), flipped: false) { _ in
            NSColor.lightGray.setFill()
            NSBezierPath(rect: CGRect(x: 40, y: 40, width: 2, height: 2)).fill()
            return true
        }))
        XCTAssertFalse(LearningStudyInput.isBlank(visible))
    }

    func testWorkspaceMapAndProofEvidenceRoundTripAndLegacyDecode() throws {
        let unit = try XCTUnwrap(LearningStudyPlannerService.validate(planResponse(source: source, core: [0]), source: source, corePages: [0]).first)
        let map = LearningStudyMap(pageSignatures: [LearningStudyInput.signature(studyText)], pages: [.init(pageIndex: 0, status: .mapped)], units: [unit])
        let workspace = DocumentWorkspace(documentURL: URL(fileURLWithPath: "/tmp/fixture.pdf"),
            learningSessions: [passedSession(target: unit.targets[1])], learningStudyMap: map)
        let data = try JSONEncoder().encode(workspace)
        let decoded = try JSONDecoder().decode(DocumentWorkspace.self, from: data)
        XCTAssertEqual(decoded.learningStudyMap?.units, [unit])
        XCTAssertEqual(decoded.learningSessions[0].studyTarget, unit.targets[1])
        XCTAssertEqual(decoded.learningSessions[0].latestExitAttempt?.assessment.criteria?.count, 3)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "learningStudyMap")
        XCTAssertNil(try JSONDecoder().decode(DocumentWorkspace.self, from: JSONSerialization.data(withJSONObject: legacy)).learningStudyMap)
    }

    private func proofQuestion(hints: [String] = []) -> LearningQuestion {
        .init(prompt: "Prove T(0)=0 using scalar preservation. \(hints.isEmpty ? "Independent question" : "Guided question")",
              expectedAnswer: "Apply scalar preservation: T(0v)=0T(v)=0. Since 0v=0, T(0)=0.",
              hints: hints, kind: .proof, gradingCriteria: proofRubric)
    }

    private func proofAssessment(outcomes: [LearningCriterionAssessment.Outcome]) -> LearningAssessment {
        .init(grade: .correct, feedback: "You used scalar preservation.", nextStep: "Check the justification of the zero scalar step.",
              criteria: outcomes.enumerated().map { .init(index: $0.offset, outcome: $0.element, feedback: "Evidence about this logical step.") })
    }

    private func fixtureLesson() -> LearningLesson {
        var diagnostic = proofQuestion()
        diagnostic = .init(prompt: "Which hypothesis permits use of scalar preservation?", expectedAnswer: diagnostic.expectedAnswer,
            hints: [], kind: .proof, gradingCriteria: proofRubric)
        return .init(title: "Linear maps and zero", objective: "Prove T(0)=0.", sourceQuote: studyQuote,
            explanation: "Use scalar multiplication.", workedExample: "A matrix preserves scalar multiplication.",
            diagnostic: diagnostic, practice: proofQuestion(hints: ["Try the scalar zero."]), exitCheck: proofQuestion())
    }

    private func fixtureProof() -> LearningProof {
        .init(statement: "T(0) = 0 for a linear map T.", assumptions: ["T preserves scalar multiplication."],
            strategy: "Apply scalar preservation with scalar zero.",
            steps: [.init(claim: "T(0v) = 0T(v)", justification: "Scalar preservation with scalar zero."),
                    .init(claim: "T(0) = 0", justification: "Zero scalar multiplication yields the zero vector in both spaces.")],
            conclusion: "A linear map sends the zero vector to the zero vector.", sourceQuote: proofQuote)
    }

    private func passedSession(target: LearningStudyTarget, help: Bool = false) -> LearningSession {
        var session = LearningSession(source: source, lesson: fixtureLesson(), providerID: "fixture", modelID: nil)
        session.studyTarget = target
        session.phase = .complete
        var question = session.lesson.exitCheck
        question.kind = target.kind
        session.attempts = [.init(phase: .exitCheck, question: question, answer: "A complete justified answer",
            assessment: proofAssessment(outcomes: [.met, .met, .met]), assistanceUsed: help, providerID: "fixture", modelID: nil)]
        return session
    }
}
