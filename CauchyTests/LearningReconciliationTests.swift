import AppKit
import PDFKit
import XCTest
@testable import Cauchy

private let reconciliationStatement = "Theorem 1.2.3. Every linear map sends zero to zero."
private let reconciliationProof = "Proof. By scalar preservation T(0v) = 0T(v), hence T(0) = 0."

@MainActor
private final class ReconciliationStub: LearningSourceReconcilerProtocol {
    var providerID = "fixture"
    var modelID: String? = "fixture-model"
    var sourceLimit = 38_000
    var calls = 0
    var failAt: Int?
    var delayAt: Int?
    var requestedPages: [Int] = []
    var sources: [LearningSource] = []
    var overrideResponse: LearningReconciliationResponse?
    var continuation: CheckedContinuation<LearningReconciliationResponse, Never>?
    var delayedResponse: LearningReconciliationResponse?

    func review(unit: LearningStudyUnit, source: LearningSource, pageCount: Int) async throws -> LearningReconciliationResponse {
        calls += 1
        sources.append(source)
        if let overrideResponse { return overrideResponse }
        if calls == failAt { throw ReadingAssistantError.api("Interrupted source review") }
        let response = LearningReconciliationResponse(issues: unit.gaps.indices.map { .init(gapIndex: $0,
            disposition: .foundElsewhere, explanation: "The argument is on the later page; study its scalar-preservation step.",
            evidence: [.init(pageIndex: 2, quote: reconciliationProof)]) }, requestedPages: requestedPages,
            proofObjective: "Prove that a linear map sends zero to zero using scalar preservation.",
            proofEvidence: [.init(pageIndex: 2, quote: reconciliationProof)])
        requestedPages = []
        if calls == delayAt {
            delayedResponse = response
            return await withCheckedContinuation { continuation = $0 }
        }
        return response
    }
}

@MainActor
final class LearningReconciliationTests: XCTestCase {
    func testCorrectedAnchorRecoversTheSameTopicWithoutReplacingItsOriginalOrTargets() throws {
        let originalQuote = "The Euclidean norm is x*x+y*y for real coordinates x and y."
        let correctedQuote = "The Euclidean norm is sqrt(x*x+y*y) for real coordinates x and y."
        let id = UUID()
        let target = LearningStudyTarget(unitID: id, kind: .concept, objective: "Use the Euclidean norm with its stated domain.")
        var unit = LearningStudyUnit(id: id, title: "Euclidean norm", anchorPage: 0, sourceQuote: originalQuote,
            pageIndices: [0], prerequisites: [], proofRequired: false, proofQuote: nil,
            gaps: ["The extracted norm formula lacks a radical."], targets: [target], pendingSourceCorrection: true)
        let correction = LearningSourceCorrection(pageIndex: 0, originalText: originalQuote, correctedText: correctedQuote,
            note: "Restore the radical after comparison with the original.", previousID: nil)
        let source = LearningSource(passages: [.init(pageIndex: 0, text: correctedQuote, correction: correction)])
        let question = LearningQuestion(prompt: "Use the norm formula.", expectedAnswer: originalQuote, hints: [])
        let lesson = LearningLesson(title: "Saved original norm lesson", objective: target.objective, sourceQuote: originalQuote,
            explanation: "Original explanation", workedExample: "Original example", diagnostic: question, practice: question, exitCheck: question)
        var saved = LearningSession(source: .init(passages: [.init(pageIndex: 0, text: originalQuote)]),
            lesson: lesson, providerID: "fixture", modelID: nil)
        saved.studyTarget = target
        saved.answerDraft = "Keep my earlier reasoning."
        unit.sourceCorrectionIDs = [correction.id]
        let pending = LearningStudyRecommendation(unit: unit, target: target, session: saved)
        XCTAssertTrue(pending.requiresSourceReview)
        XCTAssertTrue(pending.canPerformAction(assistantAvailable: false, isBusy: false))
        var response = LearningReconciliationResponse(issues: [.init(gapIndex: 0, disposition: .foundElsewhere,
            explanation: "The user transcription restores the original radical.", evidence: [.init(pageIndex: 0, quote: correctedQuote)])],
            requestedPages: [], proofObjective: nil, proofEvidence: [])
        XCTAssertThrowsError(try LearningSourceReconciler.validate(response, unit: unit, source: source,
            pageCount: 1, providerID: "fixture", modelID: nil))
        response.revisedAnchor = .init(pageIndex: 0, quote: correctedQuote, correctionID: UUID())
        let review = try LearningSourceReconciler.validate(response, unit: unit, source: source,
            pageCount: 1, providerID: "fixture", modelID: nil)
        XCTAssertEqual(review.revisedAnchor?.correctionID, correction.id) // A model-supplied ID is ignored.
        unit.reconciliation = review
        unit.pendingSourceCorrection = false
        unit.sourceCorrectionIDs = [correction.id]
        XCTAssertEqual(unit.sourceQuote, originalQuote)
        XCTAssertEqual(unit.teachingAnchor.quote, correctedQuote)
        XCTAssertTrue(source.contains(quote: unit.teachingAnchor.quote))
        XCTAssertFalse(source.contains(quote: unit.sourceQuote))
        XCTAssertEqual(unit.targets, [target])
        XCTAssertEqual(unit.id, id)
        XCTAssertEqual(unit.checkedTargetCount(sessions: []), 0)
        let next = LearningStudyRecommendation(unit: unit, target: target, session: saved)
        XCTAssertTrue(next.requiresRevisedLesson)
        XCTAssertFalse(next.requiresSourceReview)
        XCTAssertEqual(next.actionLabel, "Prepare revised lesson")
        XCTAssertFalse(next.canPerformAction(assistantAvailable: false, isBusy: false))
        XCTAssertTrue(next.canPerformAction(assistantAvailable: true, isBusy: false))
        XCTAssertEqual(saved.answerDraft, "Keep my earlier reasoning.")
        let restored = try JSONDecoder().decode(LearningStudyUnit.self, from: JSONEncoder().encode(unit))
        XCTAssertEqual(restored.teachingAnchor, unit.teachingAnchor)
        response.revisedAnchor = .init(pageIndex: 1, quote: correctedQuote)
        XCTAssertThrowsError(try LearningSourceReconciler.validate(response, unit: unit, source: source,
            pageCount: 2, providerID: "fixture", modelID: nil))
    }

    func testCorrectedExistingProofCitationKeepsItsRequirementAndPassesChapterSourceValidation() throws {
        let statement = "Every linear map sends zero to zero in real vector spaces."
        let damagedProof = "Proof. Scalar preservation gives T(0v)=one*T(v), so T(0)=one."
        let correctedProof = "Proof. Scalar preservation gives T(0v)=0*T(v), so T(0)=0."
        let otherStatement = "The zero map between real vector spaces preserves sums and scalars."
        let original = [statement, damagedProof, otherStatement].joined(separator: "\n")
        let corrected = [statement, correctedProof, otherStatement].joined(separator: "\n")
        let id = UUID()
        let target = LearningStudyTarget(unitID: id, kind: .proof, objective: "Prove that linear maps preserve zero.")
        var unit = LearningStudyUnit(id: id, title: "Linear maps", anchorPage: 0, sourceQuote: statement,
            pageIndices: [0], prerequisites: [], proofRequired: true, proofQuote: damagedProof,
            gaps: ["The extracted proof formula is damaged."], targets: [target], pendingSourceCorrection: true)
        let correction = LearningSourceCorrection(pageIndex: 0, originalText: original, correctedText: corrected,
            note: "Restore the visible zero scalars.", previousID: nil)
        let source = LearningSource(passages: [.init(pageIndex: 0, text: corrected, correction: correction)])
        var response = LearningReconciliationResponse(issues: [.init(gapIndex: 0, disposition: .foundElsewhere,
            explanation: "The full corrected scalar calculation is available.", evidence: [.init(pageIndex: 0, quote: correctedProof)])],
            requestedPages: [], proofObjective: nil, proofEvidence: [])
        XCTAssertThrowsError(try LearningSourceReconciler.validate(response, unit: unit, source: source,
            pageCount: 1, providerID: "fixture", modelID: nil))
        response = .init(issues: response.issues, requestedPages: [], proofObjective: nil,
            proofEvidence: [.init(pageIndex: 0, quote: correctedProof)])
        unit.reconciliation = try LearningSourceReconciler.validate(response, unit: unit, source: source,
            pageCount: 1, providerID: "fixture", modelID: nil)
        unit.pendingSourceCorrection = false
        unit.sourceCorrectionIDs = [correction.id]
        XCTAssertEqual(unit.targets, [target])
        XCTAssertEqual(unit.proofQuote, damagedProof)
        XCTAssertEqual(unit.reconciliation?.proofEvidence.first?.correctionID, correction.id)
        XCTAssertEqual(unit.checkedTargetCount(sessions: []), 0)
        let otherID = UUID()
        let other = LearningStudyUnit(id: otherID, title: "Zero map", anchorPage: 0, sourceQuote: otherStatement,
            pageIndices: [0], prerequisites: [], proofRequired: false, proofQuote: nil, gaps: [],
            targets: [.init(unitID: otherID, kind: .concept, objective: "Recognize the zero-map definition.")])
        XCTAssertNoThrow(try LearningTutorService.validateChapterRequest(.init(moduleID: UUID(), title: "Linear consequences",
            connection: "Use zero preservation with a concrete zero map.", units: [unit, other]), source: source))
    }

    func testCorrectionRequiresConfirmationAndCurrentSourceAndKeepsAnAppendOnlyHistory() throws {
        let pdf = try pdf()
        let original = try XCTUnwrap(pdf.page(at: 0)?.string)
        let before = map(for: pdf, units: [unit(gap: "The extracted formula is damaged.")])
        let vm = LearningStudyMapViewModel(map: before)
        var saves = 0
        vm.onChange = { _ in saves += 1 }
        let corrected = original + "\nVerified formula: the Euclidean norm is sqrt(x*x+y*y)."
        let target = before.units[0].targets[0]
        let question = LearningQuestion(prompt: "State the claim", expectedAnswer: reconciliationStatement, hints: [], kind: .concept)
        let lesson = LearningLesson(title: "Saved lesson", objective: target.objective, sourceQuote: reconciliationStatement,
            explanation: "Saved explanation", workedExample: "Saved example", diagnostic: question, practice: question, exitCheck: question)
        var savedSession = LearningSession(source: .init(passages: [.init(pageIndex: 0, text: original)]),
            lesson: lesson, providerID: "fixture", modelID: nil)
        savedSession.studyTarget = target
        savedSession.answerDraft = "Preserve this learner draft."
        savedSession.attempts = [.init(phase: .exitCheck, question: question, answer: "A saved unassisted answer",
            assessment: .init(grade: .correct, feedback: "Correct on this source version", nextStep: "Return later"),
            assistanceUsed: false, providerID: "fixture", modelID: nil)]
        let savedBytes = try JSONEncoder().encode(savedSession)
        XCTAssertEqual(before.units[0].checkedTargetCount(sessions: [savedSession]), 1)
        XCTAssertThrowsError(try vm.saveCorrection(pageIndex: 0, originalText: original, correctedText: corrected, note: "Restore radical", confirmed: false))
        XCTAssertThrowsError(try vm.saveCorrection(pageIndex: 0, originalText: original + "different PDF", correctedText: corrected, note: "Restore radical", confirmed: true))
        XCTAssertThrowsError(try vm.saveCorrection(pageIndex: 0, originalText: original, correctedText: corrected, note: "", confirmed: true))
        XCTAssertEqual(vm.map, before)
        XCTAssertEqual(saves, 0)
        try vm.saveCorrection(pageIndex: 0, originalText: original, correctedText: corrected, note: "Restore the radical after visual comparison", confirmed: true)
        let first = try XCTUnwrap(vm.map?.sourceCorrections?.first)
        try vm.saveCorrection(pageIndex: 0, originalText: original, correctedText: corrected + "\nThe variables are real.", note: "Include the visible domain", confirmed: true)
        let revisions = try XCTUnwrap(vm.map?.sourceCorrections)
        XCTAssertEqual(revisions.count, 2)
        XCTAssertEqual(revisions[0], first)
        XCTAssertEqual(revisions[1].previousID, first.id)
        XCTAssertTrue(revisions.allSatisfy { $0.originalText == original })
        XCTAssertEqual(vm.map?.units.map(\.id), before.units.map(\.id))
        XCTAssertEqual(vm.map?.units.map(\.targets), before.units.map(\.targets))
        XCTAssertEqual(vm.map?.units.first?.pendingSourceCorrection, true)
        XCTAssertTrue(vm.map?.units.first?.hasUnlocatedProof == true)
        XCTAssertEqual(vm.map?.units.first?.checkedTargetCount(sessions: []), 0)
        XCTAssertEqual(vm.map?.units.first?.checkedTargetCount(sessions: [savedSession]), 0)
        XCTAssertEqual(try JSONDecoder().decode(LearningSession.self, from: savedBytes), savedSession)
        XCTAssertEqual(saves, 2)
        let restored = try JSONDecoder().decode(LearningStudyMap.self, from: JSONEncoder().encode(vm.map!))
        XCTAssertEqual(restored.sourceCorrections, revisions)
        XCTAssertEqual(restored.units, vm.map?.units)
    }

    func testCorrectionSourceIsLabelledAndOldOrForgedCitationsFailFreshness() throws {
        let pdf = try pdf()
        let original = try XCTUnwrap(pdf.page(at: 0)?.string)
        let vm = LearningStudyMapViewModel(map: map(for: pdf, units: [unit()]))
        try vm.saveCorrection(pageIndex: 0, originalText: original, correctedText: original + "\nA user-verified mathematical correction.", note: "Compared with rendered page", confirmed: true)
        let map = try XCTUnwrap(vm.map)
        let source = try LearningSourceBuilder.pages(1...1, in: pdf, map: map)
        XCTAssertNotNil(source.passages.first?.correction)
        XCTAssertTrue(source.label.contains("user-verified transcription"))
        XCTAssertTrue(source.prompt.contains("USER-VERIFIED TRANSCRIPTION"))
        XCTAssertTrue(LearningSourceBuilder.matches(source, document: pdf, map: map))
        XCTAssertFalse(LearningSourceBuilder.matches(source, document: pdf))
        XCTAssertFalse(LearningSourceBuilder.matches(.init(passages: [.init(pageIndex: 0, text: original)]), document: pdf, map: map))
        var forged = source
        forged = .init(passages: [.init(pageIndex: 0, text: "Unverified replacement mathematical statement", correction: source.passages[0].correction)])
        XCTAssertFalse(LearningSourceBuilder.matches(forged, document: pdf, map: map))
        try vm.saveCorrection(pageIndex: 0, originalText: original, correctedText: original + "\nA second user-verified correction.", note: "Rechecked the symbol", confirmed: true)
        XCTAssertFalse(LearningSourceBuilder.matches(source, document: pdf, map: vm.map))
        let changedPDF = try self.pdf([original + "replacement file"])
        XCTAssertFalse(LearningSourceBuilder.matches(source, document: changedPDF, map: map))
        XCTAssertThrowsError(try map.passage(pageIndex: 0, originalText: "other PDF"))
    }

    func testValidatedTranscriptionReviewDoesNotWaiveAnOmittedProof() async throws {
        let pdf = try pdf([reconciliationStatement + " The proof is explicitly omitted from these notes."])
        let original = try XCTUnwrap(pdf.page(at: 0)?.string)
        let id = UUID()
        let unit = LearningStudyUnit(id: id, title: "A damaged statement with an omitted proof", anchorPage: 0,
            sourceQuote: reconciliationStatement, pageIndices: [0], prerequisites: [], proofRequired: true,
            proofQuote: nil, gaps: ["The extracted formula is damaged.", "The proof is explicitly omitted."],
            targets: [.init(unitID: id, kind: .concept, objective: "State the claim with its hypotheses.")])
        let reviewer = ReconciliationStub()
        let vm = LearningStudyMapViewModel(map: map(for: pdf, units: [unit]), reconciler: reviewer)
        let corrected = original + "\nVerified formula: sqrt(x*x+y*y)."
        try vm.saveCorrection(pageIndex: 0, originalText: original, correctedText: corrected, note: "Restore visible radical", confirmed: true)
        let evidence = [LearningSourceEvidence(pageIndex: 0, quote: corrected)]
        reviewer.overrideResponse = .init(issues: [
            .init(gapIndex: 0, disposition: .foundElsewhere, explanation: "The user's transcription restores the visible radical.", evidence: evidence),
            .init(gapIndex: 1, disposition: .omitted, explanation: "The proof remains explicitly omitted.", evidence: evidence)],
            requestedPages: [], proofObjective: nil, proofEvidence: [])
        vm.reconcile(document: pdf, unitID: id)
        await vm.waitForOperation()
        XCTAssertNil(vm.errorMessage)
        let reviewed = try XCTUnwrap(vm.map?.units.first)
        XCTAssertEqual(reviewed.pendingSourceCorrection, false)
        XCTAssertFalse(reviewed.needsSourceReview)
        XCTAssertEqual(reviewed.openGapCount, 1)
        XCTAssertTrue(reviewed.hasUnlocatedProof)
        XCTAssertEqual(reviewed.targets, unit.targets)
        XCTAssertEqual(reviewed.checkedTargetCount(sessions: []), 0)
        XCTAssertNotNil(reviewer.sources.first?.passages.first?.correction)
        XCTAssertEqual(reviewed.reconciliation?.issues.first?.evidence.first?.correctionID, vm.map?.sourceCorrections?.first?.id)
        let savedReview = try JSONDecoder().decode(LearningUnitReconciliation.self,
            from: JSONEncoder().encode(try XCTUnwrap(reviewed.reconciliation)))
        XCTAssertEqual(savedReview.issues.first?.evidence.first?.correctionID, vm.map?.sourceCorrections?.first?.id)
        // An ordinary PDF quote or an unverified model rewrite cannot use
        // this exception to the visual extraction-warning gate.
        XCTAssertThrowsError(try LearningSourceReconciler.validate(reviewer.overrideResponse!, unit: unit,
            source: .init(passages: [.init(pageIndex: 0, text: corrected)]), pageCount: 1, providerID: "fixture", modelID: nil))
    }

    func testCancelledCorrectionReviewRetainsPendingStateAndPreviousWork() async throws {
        let pdf = try pdf()
        let reviewer = ReconciliationStub()
        reviewer.delayAt = 1
        let original = try XCTUnwrap(pdf.page(at: 0)?.string)
        let vm = LearningStudyMapViewModel(map: map(for: pdf, units: [unit()]), reconciler: reviewer)
        try vm.saveCorrection(pageIndex: 0, originalText: original, correctedText: original + "\nA verified transcription amendment.", note: "Compared with the PDF", confirmed: true)
        let checkpoint = vm.map
        vm.reconcile(document: pdf)
        for _ in 0..<2000 where reviewer.continuation == nil { await Task.yield() }
        let continuation = try XCTUnwrap(reviewer.continuation)
        vm.cancel()
        continuation.resume(returning: try XCTUnwrap(reviewer.delayedResponse))
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(vm.map, checkpoint)
        XCTAssertEqual(vm.map?.units.first?.pendingSourceCorrection, true)
    }

    func testCapturedIncompleteChapterNamesActualExtractionAndProofObligations() throws {
        struct Fixture: Decodable {
            struct Review: Decodable { let studyUnit: LearningStudyUnit }
            let reviews: [Review]
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let fixture = try decoder.decode(Fixture.self, from: Data(contentsOf: root
            .appendingPathComponent("docs/evaluation/source-reconciliation-results.json")))
        let damaged = try XCTUnwrap(fixture.reviews.map(\.studyUnit).first { $0.title == "Euclidean size and distance for vectors" })
        let chainRule = try XCTUnwrap(fixture.reviews.map(\.studyUnit).first { $0.title.hasPrefix("Multivariable chain rule") })
        let units = [damaged, chainRule]
        let module = LearningCourse.Module(title: "Differentiation", goal: "Connect distances and differentiation", unitIDs: units.map(\.id))
        let map = LearningStudyMap(pageSignatures: [], pages: (0..<77).map { .init(pageIndex: $0, status: .mapped) }, units: units,
            course: .init(title: "Audit", overview: "Captured source observations", modules: [module], connections: [
                .init(fromUnitID: damaged.id, toUnitID: chainRule.id, reason: "Distance supports the derivative definition.")]))
        let before = map
        let availability = map.chapterAvailability(for: module)
        XCTAssertNil(availability.request)
        XCTAssertTrue(availability.blockers.contains { $0.kind == .extraction && $0.unitID == damaged.id && $0.pageIndex == 4 })
        XCTAssertTrue(availability.blockers.contains { $0.kind == .proof && $0.unitID == chainRule.id })
        XCTAssertTrue(availability.blockers.contains { $0.reason.contains("Explicitly omitted") && $0.unitID == chainRule.id })
        XCTAssertEqual(Set(availability.blockers.map(\.id)).count, availability.blockers.count)
        XCTAssertEqual(map, before)
        XCTAssertEqual(map.units.reduce(0) { $0 + $1.checkedTargetCount(sessions: []) }, 0)
    }

    func testApprovedRealSourceFixtureOffersReviewAndOtherWorkWithoutClearingObligations() throws {
        struct Fixture: Decodable {
            struct Review: Decodable { let studyUnit: LearningStudyUnit }
            let reviews: [Review]
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let fixture = try decoder.decode(Fixture.self, from: Data(contentsOf: root
            .appendingPathComponent("docs/evaluation/source-reconciliation-results.json")))
        let units = fixture.reviews.map(\.studyUnit)
        let course = LearningCourse(title: "Source recovery fixture", overview: "Captured source-only checks.",
            modules: [.init(title: "Audited topics", goal: "Retain unresolved source obligations.", unitIDs: units.map(\.id))], connections: [])
        let map = LearningStudyMap(pageSignatures: [], pages: [], units: units, course: course)
        let before = map
        let next = try XCTUnwrap(map.nextStudy(sessions: []))
        XCTAssertEqual(next.unit.title, "Euclidean size and distance for vectors")
        XCTAssertEqual(next.actionLabel, "Review source")
        XCTAssertTrue(next.canPerformAction(assistantAvailable: false, isBusy: false))
        XCTAssertEqual(next.sourceReviewPageIndex, 4)
        let choices = map.availableStudyChoices(sessions: [])
        XCTAssertFalse(choices.contains { $0.unit.id == next.unit.id })
        let chainRule = try XCTUnwrap(units.first { $0.title.hasPrefix("Multivariable chain rule") })
        XCTAssertTrue(choices.contains { $0.unit.id == chainRule.id })
        XCTAssertTrue(chainRule.hasUnlocatedProof)
        XCTAssertEqual(chainRule.openGapCount, 3)
        XCTAssertTrue(chainRule.reconciliation!.issues.contains { $0.disposition == .omitted })
        XCTAssertEqual(map.units.reduce(0) { $0 + $1.checkedTargetCount(sessions: []) }, 0)
        XCTAssertEqual(map, before)
    }

    func testProbeAcceptsCanonicalTemporaryAliasesAndRejectsEscapingSymlink() throws {
        XCTAssertNotNil(LearningSourceReconciliationProbe.isolatedOutputURL("/tmp/cauchy-source-check"))
        XCTAssertNotNil(LearningSourceReconciliationProbe.isolatedOutputURL("/private/tmp/cauchy-source-check"))
        XCTAssertNil(LearningSourceReconciliationProbe.isolatedOutputURL("/tmp"))
        XCTAssertNil(LearningSourceReconciliationProbe.isolatedOutputURL(NSHomeDirectory()))
        let link = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: NSHomeDirectory()))
        defer { try? FileManager.default.removeItem(at: link) }
        XCTAssertNil(LearningSourceReconciliationProbe.isolatedOutputURL(link.appendingPathComponent("source-check").path))
    }

    private var pages: [String] {
        [reconciliationStatement, "The next section continues with examples and notation.", reconciliationProof]
    }

    private func unit(gap: String = "The proof is absent from the local excerpt.", anchor: Int = 0) -> LearningStudyUnit {
        let id = UUID()
        return .init(id: id, title: "Linear maps and zero", anchorPage: anchor, sourceQuote: reconciliationStatement,
            pageIndices: [anchor], prerequisites: [], proofRequired: true, proofQuote: nil, gaps: [gap],
            targets: [.init(unitID: id, kind: .concept, objective: "State the linear-map zero property.")])
    }

    private func response(disposition: LearningGapDisposition = .foundElsewhere, evidence: [LearningSourceEvidence]? = nil,
                          proof: Bool = true) -> LearningReconciliationResponse {
        let evidence = evidence ?? [.init(pageIndex: 2, quote: reconciliationProof)]
        return .init(issues: [.init(gapIndex: 0, disposition: disposition, explanation: "Check the exact source argument.", evidence: evidence)],
            requestedPages: [], proofObjective: proof ? "Prove that a linear map sends zero to zero using scalar preservation." : nil,
            proofEvidence: proof ? evidence : [])
    }

    private var source: LearningSource {
        .init(passages: pages.enumerated().map { .init(pageIndex: $0.offset, text: $0.element) })
    }

    private func validate(_ response: LearningReconciliationResponse, unit: LearningStudyUnit) throws -> LearningUnitReconciliation {
        try LearningSourceReconciler.validate(response, unit: unit, source: source, pageCount: pages.count,
            providerID: "fixture", modelID: "fixture-model")
    }

    func testProofElsewhereAddsUncheckedRequirementWithoutChangingOriginalIDs() throws {
        var unit = unit()
        let original = unit.targets
        unit.reconciliation = try validate(response(), unit: unit)
        XCTAssertEqual(unit.targets, original)
        XCTAssertEqual(unit.learningTargets.map(\.kind), [.concept, .proof])
        XCTAssertEqual(unit.learningPageIndices, [0, 2])
        XCTAssertEqual(unit.openGapCount, 0)
        XCTAssertTrue(unit.proofRequired)
        XCTAssertNil(unit.proofQuote)
        XCTAssertEqual(unit.checkedTargetCount(sessions: []), 0)
        XCTAssertFalse(unit.hasEvidenceForEveryTarget(sessions: []))
        let decoded = try JSONDecoder().decode(LearningStudyUnit.self, from: JSONEncoder().encode(unit))
        XCTAssertEqual(decoded.learningTargets.map(\.id), unit.learningTargets.map(\.id))
        XCTAssertEqual(decoded.gaps, unit.gaps)
        let previousProofID = unit.reconciliation?.proofTarget?.id
        let updatedResponse = LearningReconciliationResponse(issues: response().issues, requestedPages: [],
            proofObjective: "Reconstruct the same zero-vector proof with explicit scalar justifications.", proofEvidence: response().proofEvidence)
        let updated = try validate(updatedResponse, unit: unit)
        XCTAssertEqual(updated.proofTarget?.id, previousProofID)
        XCTAssertEqual(unit.targets, original)
    }

    func testExplicitOmissionStaysOpenAndCannotCreateProofTarget() throws {
        var unit = unit()
        let quote = "The proof of this theorem is omitted from these notes."
        let source = LearningSource(passages: [.init(pageIndex: 0, text: quote)])
        let omitted = response(disposition: .omitted, evidence: [.init(pageIndex: 0, quote: quote)], proof: false)
        unit.reconciliation = try LearningSourceReconciler.validate(omitted, unit: unit, source: source, pageCount: 1,
            providerID: "fixture", modelID: nil)
        XCTAssertEqual(unit.openGapCount, 1)
        XCTAssertEqual(unit.learningTargets.count, 1)
        XCTAssertTrue(unit.proofRequired)
        XCTAssertThrowsError(try validate(response(disposition: .omitted), unit: unit))
    }

    func testSearchMissIsNotProofOfOmission() throws {
        let unit = unit()
        XCTAssertThrowsError(try validate(response(disposition: .omitted, evidence: [], proof: false), unit: unit))
        let unresolved = try validate(response(disposition: .notLocated, evidence: [], proof: false), unit: unit)
        XCTAssertEqual(unresolved.issues[0].disposition, .notLocated)
        XCTAssertNil(unresolved.proofTarget)
    }

    func testDamagedFormulaCannotBeSilentlyResolvedFromAnotherTextQuote() throws {
        var unit = unit(gap: "The extracted Euclidean formula lacks a square root; verify the original typesetting.")
        XCTAssertThrowsError(try validate(response(), unit: unit))
        unit.reconciliation = try validate(response(disposition: .extractionProblem, proof: false), unit: unit)
        XCTAssertTrue(unit.needsSourceReview)
        XCTAssertEqual(unit.openGapCount, 1)
        XCTAssertEqual(unit.learningPageIndices, [0])
        XCTAssertThrowsError(try validate(response(evidence: [.init(pageIndex: 2, quote: "Proof. A silently repaired radical and a fabricated source quotation.")]), unit: unit))
    }

    func testEvidenceMustComeFromTheStatedPageAndEveryCandidateMustSurvive() throws {
        let unit = unit()
        XCTAssertThrowsError(try validate(response(evidence: [.init(pageIndex: 0, quote: reconciliationProof)]), unit: unit))
        let missing = LearningReconciliationResponse(issues: [], requestedPages: [], proofObjective: nil, proofEvidence: [])
        XCTAssertThrowsError(try validate(missing, unit: unit))
        let duplicate = LearningReconciliationResponse(issues: response().issues + response().issues,
            requestedPages: [], proofObjective: nil, proofEvidence: [])
        XCTAssertThrowsError(try validate(duplicate, unit: unit))
    }

    func testWholeDocumentRetrievalFindsDistantNumberedReferenceAndNeverClipsPages() throws {
        var pages = Array(repeating: "Unrelated contents and administrative page material.", count: 30)
        pages[0] = reconciliationStatement + " See Lemma 8.1.6."
        pages[29] = "Lemma 8.1.6. " + reconciliationProof
        let search = LearningDocumentSearch(pages: pages)
        XCTAssertTrue(search.rankedPages(unit: unit()).contains(29))
        let retrieved = try XCTUnwrap(search.initialSource(unit: unit(), limit: 1000))
        XCTAssertTrue(retrieved.passages.contains { $0.pageIndex == 29 && $0.text == pages[29] })
        XCTAssertNil(search.initialSource(unit: unit(), limit: 20))
    }

    private func pdf(_ texts: [String]? = nil) throws -> PDFDocument {
        let data = NSMutableData()
        var bounds = CGRect(x: 0, y: 0, width: 600, height: 800)
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &bounds, nil))
        for text in texts ?? pages {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12)])
                .draw(in: CGRect(x: 30, y: 400, width: 530, height: 340))
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
        return try XCTUnwrap(PDFDocument(data: data as Data))
    }

    private func map(for pdf: PDFDocument, units: [LearningStudyUnit]) -> LearningStudyMap {
        .init(pageSignatures: (0..<pdf.pageCount).map { LearningStudyInput.signature(pdf.page(at: $0)!.string!) },
            pages: (0..<pdf.pageCount).map { .init(pageIndex: $0, status: .mapped) }, units: units)
    }

    func testInterruptionResumesAtNextTopicAndPreservesSavedProofTarget() async throws {
        let pdf = try pdf()
        let reviewer = ReconciliationStub()
        reviewer.failAt = 2
        let original = map(for: pdf, units: [unit(), unit()])
        let vm = LearningStudyMapViewModel(map: original, reconciler: reviewer)
        var saved: LearningStudyMap?
        vm.onChange = { saved = $0 }
        vm.reconcile(document: pdf)
        await vm.waitForOperation()
        XCTAssertNotNil(vm.errorMessage)
        let checkpoint = try XCTUnwrap(saved)
        XCTAssertNotNil(checkpoint.units[0].reconciliation)
        XCTAssertNil(checkpoint.units[1].reconciliation)
        reviewer.failAt = nil
        let resumed = LearningStudyMapViewModel(map: try JSONDecoder().decode(LearningStudyMap.self,
            from: JSONEncoder().encode(checkpoint)), reconciler: reviewer)
        resumed.reconcile(document: pdf)
        await resumed.waitForOperation()
        XCTAssertNil(resumed.errorMessage)
        XCTAssertEqual(reviewer.calls, 3)
        XCTAssertEqual(resumed.map?.units[0].reconciliation?.proofTarget?.id, checkpoint.units[0].reconciliation?.proofTarget?.id)
        XCTAssertEqual(resumed.map?.units.map(\.targets), original.units.map(\.targets))
        XCTAssertEqual(resumed.map?.units.map(\.id), original.units.map(\.id))
    }

    func testCancelRejectsLateReviewAndRetainsEarlierCheckpoint() async throws {
        let pdf = try pdf()
        let reviewer = ReconciliationStub()
        reviewer.delayAt = 2
        let vm = LearningStudyMapViewModel(map: map(for: pdf, units: [unit(), unit()]), reconciler: reviewer)
        vm.reconcile(document: pdf)
        for _ in 0..<2000 where reviewer.continuation == nil { await Task.yield() }
        XCTAssertNotNil(reviewer.continuation)
        XCTAssertNotNil(vm.map?.units[0].reconciliation)
        vm.cancel()
        reviewer.continuation?.resume(returning: try XCTUnwrap(reviewer.delayedResponse))
        for _ in 0..<100 { await Task.yield() }
        XCTAssertNil(vm.map?.units[1].reconciliation)
        XCTAssertFalse(vm.isReconciling)
        XCTAssertFalse(vm.isBusy)
    }

    func testChangedSourceCannotReuseReviewAndLegacyMapDecodes() async throws {
        let pdf = try pdf()
        let reviewer = ReconciliationStub()
        var original = map(for: pdf, units: [unit()])
        original = .init(pageSignatures: ["stale"], pages: original.pages, units: original.units)
        let vm = LearningStudyMapViewModel(map: original, reconciler: reviewer)
        vm.reconcile(document: pdf)
        await vm.waitForOperation()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertEqual(reviewer.calls, 0)
        let decoded = try JSONDecoder().decode(LearningStudyMap.self, from: JSONEncoder().encode(original))
        XCTAssertNil(decoded.units[0].reconciliation)
    }

    func testReconciliationSurvivesStaleReaderSaveWithoutChangingDraftOrAssistance() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = DocumentPersistenceService(root: root)
        let question = LearningQuestion(prompt: "Explain why zero is preserved.", expectedAnswer: reconciliationProof, hints: [])
        let lesson = LearningLesson(title: "Linear maps", objective: "Justify preservation of zero.",
            sourceQuote: reconciliationStatement, explanation: "Use scalar preservation.", workedExample: reconciliationProof,
            diagnostic: question, practice: question, exitCheck: question)
        var session = LearningSession(source: source, lesson: lesson, providerID: "fixture", modelID: nil)
        session.answerDraft = "Keep this unfinished reasoning."
        session.hintsRevealed = 1
        session.attempts = [.init(phase: .practice, question: question, answer: "My first argument",
            assessment: .init(grade: .partial, feedback: "Justify the scalar step.", nextStep: "Explain why zero scalar multiplication applies."),
            assistanceUsed: true, providerID: "fixture", modelID: nil)]
        let pdf = try pdf()
        let initial = DocumentWorkspace(documentURL: URL(fileURLWithPath: "/tmp/reconciliation-progress.pdf"),
            learningSessions: [session], learningStudyMap: map(for: pdf, units: [unit()]))
        try await persistence.saveWorkspace(initial, bookmarkData: nil)
        var changed = initial
        changed.learningStudyMap?.units[0].reconciliation = try validate(response(), unit: initial.learningStudyMap!.units[0])
        let correctedVM = LearningStudyMapViewModel(map: changed.learningStudyMap)
        let originalText = try XCTUnwrap(pdf.page(at: 0)?.string)
        try correctedVM.saveCorrection(pageIndex: 0, originalText: originalText,
            correctedText: originalText + "\nA user-verified transcription amendment.", note: "Verified against the rendered PDF", confirmed: true)
        changed.learningStudyMap = correctedVM.map
        changed.learningStudyMap?.updatedAt = Date().addingTimeInterval(1)
        try await persistence.saveWorkspace(changed, bookmarkData: nil, learningOnly: true)
        try await persistence.saveWorkspace(initial, bookmarkData: nil)
        let loaded = await persistence.loadWorkspace(id: initial.id)
        let saved = try XCTUnwrap(loaded)
        let restoredSession = try XCTUnwrap(saved.workspace.learningSessions.first)
        XCTAssertEqual(restoredSession.id, session.id)
        XCTAssertEqual(restoredSession.answerDraft, session.answerDraft)
        XCTAssertEqual(restoredSession.hintsRevealed, 1)
        XCTAssertEqual(restoredSession.attempts.map(\.id), session.attempts.map(\.id))
        XCTAssertEqual(restoredSession.attempts.map(\.answer), session.attempts.map(\.answer))
        XCTAssertEqual(restoredSession.attempts.map(\.assessment), session.attempts.map(\.assessment))
        XCTAssertEqual(restoredSession.attempts.map(\.assistanceUsed), [true])
        XCTAssertEqual(restoredSession.updatedAt.timeIntervalSince1970, session.updatedAt.timeIntervalSince1970, accuracy: 0.000001)
        let review = saved.workspace.learningStudyMap?.units[0].reconciliation
        XCTAssertEqual(review?.issues, changed.learningStudyMap?.units[0].reconciliation?.issues)
        XCTAssertEqual(review?.proofTarget, changed.learningStudyMap?.units[0].reconciliation?.proofTarget)
        XCTAssertEqual(saved.workspace.learningStudyMap?.units[0].targets, initial.learningStudyMap?.units[0].targets)
        let savedRevision = try XCTUnwrap(saved.workspace.learningStudyMap?.sourceCorrections?.first)
        let expectedRevision = try XCTUnwrap(changed.learningStudyMap?.sourceCorrections?.first)
        XCTAssertEqual(savedRevision.id, expectedRevision.id)
        XCTAssertEqual(savedRevision.originalText, expectedRevision.originalText)
        XCTAssertEqual(savedRevision.correctedText, expectedRevision.correctedText)
        XCTAssertEqual(savedRevision.note, expectedRevision.note)
        XCTAssertEqual(savedRevision.previousID, expectedRevision.previousID)
        XCTAssertEqual(savedRevision.createdAt.timeIntervalSince1970, expectedRevision.createdAt.timeIntervalSince1970, accuracy: 0.000001)
        XCTAssertEqual(saved.workspace.learningStudyMap?.units[0].pendingSourceCorrection, true)
    }

    func testReferenceRequestsAreFollowedBeforeReviewCanCommit() async throws {
        let pdf = try pdf()
        let reviewer = ReconciliationStub()
        reviewer.sourceLimit = 150
        reviewer.requestedPages = [3]
        let vm = LearningStudyMapViewModel(map: map(for: pdf, units: [unit()]), reconciler: reviewer)
        vm.reconcile(document: pdf)
        await vm.waitForOperation()
        let saved = try XCTUnwrap(vm.map?.units[0].reconciliation)
        // The complete requested page either fits or stays an explicit open
        // context requirement; no positive proof can be committed prematurely.
        if saved.proofTarget == nil {
            XCTAssertEqual(saved.issues[0].disposition, .notLocated)
            XCTAssertEqual(vm.map?.units[0].openGapCount, 1)
        } else {
            XCTAssertGreaterThan(reviewer.calls, 1)
            XCTAssertTrue(saved.inspectedPageIndices.contains(2))
        }
    }

    func testAdditionalDistantPageIsFetchedAndReviewedBeforeCommit() async throws {
        let pdf = try pdf([reconciliationStatement] + Array(repeating: reconciliationProof, count: 19))
        let reviewer = ReconciliationStub()
        reviewer.requestedPages = [20]
        let vm = LearningStudyMapViewModel(map: map(for: pdf, units: [unit()]), reconciler: reviewer)
        vm.reconcile(document: pdf)
        await vm.waitForOperation()
        XCTAssertEqual(reviewer.calls, 2)
        XCTAssertFalse(reviewer.sources[0].passages.contains { $0.pageIndex == 19 })
        XCTAssertTrue(reviewer.sources[1].passages.contains { $0.pageIndex == 19 })
        XCTAssertTrue(vm.map?.units[0].reconciliation?.inspectedPageIndices.contains(19) == true)
    }
}
