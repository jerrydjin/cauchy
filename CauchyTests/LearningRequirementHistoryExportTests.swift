import XCTest
@testable import Cauchy

@MainActor
final class LearningRequirementHistoryExportTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)
    private let target = LearningStudyTarget(unitID: UUID(), kind: .concept, objective: "Explain why a linear map preserves the zero vector.")
    private let sourceQuote = "Every linear map sends the zero vector to the zero vector."

    private func session(answer: String = "My saved reasoning.", source: LearningSource? = nil) -> LearningSession {
        func question(_ prompt: String) -> LearningQuestion {
            .init(prompt: prompt, expectedAnswer: "HIDDEN_EXPECTED_ANSWER", hints: ["HIDDEN_UNREVEALED_HINT"],
                  kind: .concept, gradingCriteria: ["Justify zero preservation."])
        }
        let lesson = LearningLesson(title: "Saved zero-vector lesson", objective: target.objective, sourceQuote: sourceQuote,
            explanation: "TEACHING_NOT_PART_OF_WORK_EXPORT", workedExample: "WORKED_EXAMPLE_NOT_PART_OF_WORK_EXPORT",
            diagnostic: question("UNSEEN_DIAGNOSTIC_PROMPT"), practice: question("Explain the zero-vector inference."),
            exitCheck: question("UNSEEN_EXIT_PROMPT"))
        var session = LearningSession(source: source ?? .init(passages: [.init(pageIndex: 0, text: sourceQuote + " RAW_NOTES_NOT_FOR_EXPORT")]),
            lesson: lesson, phase: .practice, answerDraft: answer, providerID: "Saved tutor", modelID: "Saved model",
            createdAt: date, updatedAt: date)
        session.studyTarget = target
        return session
    }

    private func export(_ sessions: [LearningSession], selected: String? = nil, currentSource: Bool = true) throws -> String {
        try XCTUnwrap(LearningRequirementHistoryExport.markdown(documentTitle: "Authored notes", target: target, sessions: sessions,
            selectedEntryID: selected, exportedAt: date, sourceIsCurrent: { _ in currentSource }))
    }

    func testDraftExportPreservesLongMathematicsWithoutHiddenOrUnrelatedContent() throws {
        let answer = "## My argument\n\n$$T(0v)=0T(v)=0$$\n```text\nA quoted calculation.\n```\n"
            + String(repeating: "Track the hypothesis and the limit.\n", count: 250) + "FINAL_REASONING_MARKER"
        let saved = session(answer: answer)
        var unrelated = session(answer: "UNRELATED_ANSWER")
        unrelated.studyTarget = .init(unitID: target.unitID, kind: .concept, objective: target.objective)
        var otherKind = session(answer: "OTHER_KIND_ANSWER")
        otherKind.studyTarget = .init(id: target.id, unitID: target.unitID, kind: .proof, objective: target.objective)
        var chapter = session(answer: "CHAPTER_ANSWER")
        let request = LearningChapterRequest(moduleID: UUID(), title: "Chapter", connection: "Connect ideas", units: [])
        chapter.chapter = .init(request: request, challenge: .init(moduleID: request.moduleID, title: "Chapter", connection: request.connection,
            ideas: [], assumptions: [], question: saved.lesson.practice, criteria: [],
            refresher: .init(unitID: UUID(), pageIndex: 0, sourceQuote: sourceQuote, explanation: "Chapter refresher", check: saved.lesson.practice)))
        let text = try export([saved, unrelated, otherKind, chapter])
        XCTAssertTrue(text.contains("1 saved record"))
        XCTAssertTrue(text.contains("**Saved status:** Unsubmitted answer"))
        XCTAssertTrue(text.contains("> ## My argument\n> \n> $$T(0v)=0T(v)=0$$\n> ```text"))
        XCTAssertTrue(text.contains("> FINAL_REASONING_MARKER"))
        XCTAssertEqual(text.components(separatedBy: "Track the hypothesis and the limit.").count - 1, 250)
        XCTAssertTrue(text.contains("No help was recorded for this question."))
        for hidden in ["HIDDEN_EXPECTED_ANSWER", "HIDDEN_UNREVEALED_HINT", "UNSEEN_DIAGNOSTIC_PROMPT", "UNSEEN_EXIT_PROMPT",
                       "TEACHING_NOT_PART_OF_WORK_EXPORT", "WORKED_EXAMPLE_NOT_PART_OF_WORK_EXPORT", "RAW_NOTES_NOT_FOR_EXPORT",
                       "UNRELATED_ANSWER", "OTHER_KIND_ANSWER", "CHAPTER_ANSWER"] {
            XCTAssertFalse(text.contains(hidden), hidden)
        }
        XCTAssertFalse(text.contains("Recorded tutor grade"))
    }

    func testAssessmentExportRetainsOriginalGradeAndHistoricalQualifications() throws {
        var saved = session()
        saved.phase = .complete
        saved.studyTarget = .init(id: target.id, unitID: target.unitID, kind: target.kind, objective: "Earlier objective wording.")
        var question = saved.lesson.practice; question.kind = nil
        saved.attempts = [.init(phase: .exitCheck, question: question, answer: "My original submitted argument.",
            assessment: .init(grade: .correct, feedback: "Original tutor feedback.", nextStep: "Original next step.",
                criteria: [.init(index: 0, outcome: .notMet, feedback: "The essential inference was not justified."),
                           .init(index: Int.max, outcome: .uncertain, feedback: "Unmatched saved criterion.")]),
            assistanceUsed: true, providerID: "Original assessment tutor", modelID: "Original assessment model", createdAt: date)]
        let text = try export([saved], currentSource: false)
        XCTAssertTrue(text.contains("**Saved status:** Assessment needs checking"))
        XCTAssertTrue(text.contains("**Recorded tutor grade:** Correct"))
        XCTAssertTrue(text.contains("The saved reasoning checks do not support a complete assessment."))
        XCTAssertTrue(text.contains("> Earlier objective wording."))
        XCTAssertTrue(text.contains("does not establish the current requirement"))
        XCTAssertTrue(text.contains("requirement kind was not recorded"))
        XCTAssertTrue(text.contains("Help was recorded for this answer."))
        XCTAssertTrue(text.contains("> Original tutor feedback."))
        XCTAssertTrue(text.contains("> Original next step."))
        XCTAssertTrue(text.contains("> Justify zero preservation."))
        XCTAssertTrue(text.contains("**Outcome:** Not met"))
        XCTAssertTrue(text.contains("Recorded check index: \(Int.max)"))
        XCTAssertTrue(text.contains("**Outcome:** Uncertain"))
        XCTAssertTrue(text.contains("source needs review against the current notes"))
        XCTAssertTrue(text.contains("2023-11-14T22:13:20.000Z"))
        XCTAssertTrue(text.contains("> Original assessment tutor / Original assessment model"))
        XCTAssertFalse(text.contains("HIDDEN_EXPECTED_ANSWER"))
    }

    func testSelectedExportIsExactAndHistoryOrderIsDeterministic() throws {
        var older = session(answer: "OLDER_ARGUMENT"); older.updatedAt = date.addingTimeInterval(-86_400)
        let newer = session(answer: "NEWER_ARGUMENT")
        let all = try export([older, newer])
        XCTAssertEqual(all, try export([newer, older]))
        XCTAssertTrue(all.contains("Requirement history · 2 saved records"))
        XCTAssertLessThan(try XCTUnwrap(all.range(of: "NEWER_ARGUMENT")?.lowerBound), try XCTUnwrap(all.range(of: "OLDER_ARGUMENT")?.lowerBound))
        let entry = try XCTUnwrap(LearningRequirementHistory.entries(for: target, in: [older]).first)
        let selected = try export([newer, older], selected: entry.id)
        XCTAssertTrue(selected.contains("Selected record · 1 saved record"))
        XCTAssertTrue(selected.contains("OLDER_ARGUMENT"))
        XCTAssertFalse(selected.contains("NEWER_ARGUMENT"))
        XCTAssertNil(LearningRequirementHistoryExport.markdown(documentTitle: "Notes", target: target, sessions: [older],
            selectedEntryID: "missing-record", sourceIsCurrent: { _ in true }))
        XCTAssertNil(LearningRequirementHistoryExport.markdown(documentTitle: "Notes", target: target, sessions: [], sourceIsCurrent: { _ in true }))
    }

    func testSourceReferencesIdentifySavedTranscriptionsWithoutDumpingNotes() throws {
        let correction = LearningSourceCorrection(pageIndex: 6, originalText: "PRIVATE_ORIGINAL_PAGE",
            correctedText: sourceQuote + " PRIVATE_CORRECTED_PAGE", note: "PRIVATE_CORRECTION_NOTE", previousID: nil, createdAt: date)
        let saved = session(source: .init(passages: [.init(pageIndex: 3, text: "Other supplied page content."),
            .init(pageIndex: 6, text: correction.correctedText, correction: correction)]))
        let text = try export([saved])
        XCTAssertTrue(text.contains("Supplied pages: PDF page 4, PDF page 7."))
        XCTAssertTrue(text.contains("PDF page 7: user-verified transcription saved at 2023-11-14T22:13:20.000Z"))
        XCTAssertTrue(text.contains("> " + sourceQuote))
        XCTAssertTrue(text.contains("Quote located in saved material on: PDF page 7."))
        XCTAssertTrue(text.contains("do not verify the tutor’s judgement"))
        for hidden in ["PRIVATE_ORIGINAL_PAGE", "PRIVATE_CORRECTED_PAGE", "PRIVATE_CORRECTION_NOTE", "Other supplied page content."] {
            XCTAssertFalse(text.contains(hidden), hidden)
        }
    }

    func testUnavailableLegacySourceIsQualifiedWithoutInventingPageReferences() throws {
        var saved = session(source: .init(passages: []))
        let missing = try export([saved], currentSource: false)
        XCTAssertTrue(missing.contains("No source pages were saved."))
        XCTAssertTrue(missing.contains("The saved quote could not be located in the recorded source."))
        saved = session(source: .init(passages: [.init(pageIndex: Int.max, text: "Unmatched source."), .init(pageIndex: -1, text: "Unmatched source.")]))
        let invalid = try export([saved], currentSource: false)
        XCTAssertTrue(invalid.contains("Recorded PDF index \(Int.max)"))
        XCTAssertTrue(invalid.contains("Recorded PDF index -1"))
        XCTAssertFalse(invalid.contains("Quote located in saved material on:"))
    }
}
