import XCTest
@testable import Cauchy

final class AskPromptBuilderTests: XCTestCase {
    private let sheet = AskProblemSheet(
        fileName: "sheet.pdf",
        extractedText: "Solve for the limit using the notes. By Theorem 3.2 the sequence converges."
    )

    private let highlight = AskHighlightFocus(
        pageIndex: 11,
        excerpt: "A function f is continuous at a when the limit equals f(a).",
        surroundingText: "The previous paragraph defines a limit.",
        fingerprint: "p12"
    )

    func testPromptWithNoHighlightIsAboutTheWholeDocument() {
        let prompt = AskPromptBuilder.modelPrompt(
            documentTitle: "Analysis Notes",
            question: "Which results apply to uniform convergence?",
            scope: .wholeDocument,
            sheet: nil,
            depth: .hint,
            provider: .onDevice
        )

        XCTAssertTrue(prompt.contains("NO PASSAGE IS HIGHLIGHTED"))
        XCTAssertTrue(prompt.contains("whole open document"))
        XCTAssertTrue(prompt.contains("Which results apply to uniform convergence?"))
        XCTAssertFalse(prompt.contains("SELECTED TEXT"))
        XCTAssertFalse(prompt.contains("HIGHLIGHTED PASSAGE"))
        XCTAssertTrue(prompt.contains("by Theorem 3.2"))
        XCTAssertTrue(prompt.contains("Lemma 2.1"))
    }

    func testPromptWithHighlightIncludesThePassage() {
        let prompt = AskPromptBuilder.modelPrompt(
            documentTitle: "Analysis Notes",
            question: "Why is this continuous?",
            scope: .highlight(highlight),
            sheet: nil,
            depth: .hint,
            provider: .onDevice
        )

        XCTAssertTrue(prompt.contains("SELECTED TEXT"))
        XCTAssertTrue(prompt.contains(highlight.excerpt))
        XCTAssertTrue(prompt.contains("PDF page 12"))
        XCTAssertTrue(prompt.contains("Why is this continuous?"))
        XCTAssertFalse(prompt.contains("NO PASSAGE IS HIGHLIGHTED"))
    }

    func testPromptWithAttachedSheetIncludesExtractedText() {
        let prompt = AskPromptBuilder.modelPrompt(
            documentTitle: "Analysis Notes",
            question: "How do I start this problem?",
            scope: .wholeDocument,
            sheet: sheet,
            depth: .hint,
            provider: .onDevice
        )

        XCTAssertTrue(prompt.contains("ATTACHED PROBLEM SHEET (sheet.pdf)"))
        XCTAssertTrue(prompt.contains("By Theorem 3.2 the sequence converges."))
        XCTAssertTrue(prompt.contains("How do I start this problem?"))
        XCTAssertTrue(prompt.contains("whole open document"))
    }

    func testHintPromptDoesNotAskForTheFullSolution() {
        let prompt = AskPromptBuilder.modelPrompt(
            documentTitle: "Notes",
            question: "Prove it.",
            scope: .wholeDocument,
            sheet: nil,
            depth: .hint,
            provider: .onDevice
        )

        XCTAssertTrue(prompt.contains("Give a hint or an approach only"))
        XCTAssertTrue(prompt.contains("Do not write the full worked solution."))
        XCTAssertFalse(prompt.contains("Give the full worked solution"))
    }

    func testFullSolutionPromptAsksForTheWorkedSolution() {
        let prompt = AskPromptBuilder.modelPrompt(
            documentTitle: "Notes",
            question: "Show the full worked solution for: Prove it.",
            scope: .highlight(highlight),
            sheet: sheet,
            depth: .fullSolution,
            provider: .anthropicAPI
        )

        XCTAssertTrue(prompt.contains("Give the full worked solution, step by step"))
        XCTAssertFalse(prompt.contains("Do not write the full worked solution."))
        XCTAssertTrue(prompt.contains(highlight.excerpt))
        XCTAssertTrue(prompt.contains("sheet.pdf"))
    }

    func testOnDeviceSheetAndHistoryStayInsideTheContextBudget() {
        let longSheet = String(repeating: "A", count: 5_000)
        let clipped = AskPromptBuilder.clippedSheetText(longSheet, provider: .onDevice)
        XCTAssertEqual(clipped.count, AskPromptBuilder.onDeviceSheetCharacters)
        XCTAssertGreaterThan(
            AskPromptBuilder.clippedSheetText(longSheet, provider: .anthropicAPI).count,
            AskPromptBuilder.onDeviceSheetCharacters
        )

        let older = ThreadMessage(role: .user, content: String(repeating: "q", count: 1_300))
        let middle = ThreadMessage(role: .assistant, content: String(repeating: "a", count: 1_300))
        let latest = ThreadMessage(role: .user, content: "latest question")
        let trimmed = AskPromptBuilder.trimmedHistory([older, middle, latest], provider: .onDevice)

        XCTAssertEqual(trimmed, [latest])
        XCTAssertLessThanOrEqual(
            trimmed.reduce(0) { $0 + $1.content.count },
            AskPromptBuilder.onDeviceHistoryCharacters
        )

        let cloud = AskPromptBuilder.trimmedHistory([older, middle, latest], provider: .anthropicAPI)
        XCTAssertEqual(cloud.count, 3)
    }

    func testWholeDocumentInstructionsStillRequireAnEvidenceBoundary() {
        let prompt = AskPromptBuilder.sessionInstructions(
            documentTitle: "Notes",
            scope: .wholeDocument,
            provider: .onDevice
        )
        XCTAssertTrue(prompt.contains("[[CAUCHY_BASIS: PDF]]"))
        XCTAssertTrue(prompt.contains("[[CAUCHY_BASIS: MIXED]]"))
        XCTAssertTrue(prompt.contains("[[CAUCHY_BASIS: INSUFFICIENT]]"))
        XCTAssertTrue(prompt.contains("do not guess"))
    }

    func testCitationValidationLinksOnlyResultsThatExist() {
        let known: Set<ReferenceKey> = [
            ReferenceKey(kind: .theorem, number: "3.2"),
            ReferenceKey(kind: .lemma, number: "2.1"),
        ]
        let answer = "Use the estimate by Theorem 3.2, then Lemma 2.1. Theorem 9.9 is not in these notes, nor is Lemma 8.4."

        let linked = AssistantResponseValidator.linkableReferences(in: answer, known: known)
        XCTAssertEqual(linked.map(\.reference.displayName), ["Theorem 3.2", "Lemma 2.1"])

        let unlinked = AssistantResponseValidator.unlinkableReferences(in: answer, known: known)
        XCTAssertEqual(unlinked.map(\.displayName), ["Theorem 9.9", "Lemma 8.4"])
        XCTAssertTrue(AssistantResponseValidator.linkableReferences(in: answer, known: []).isEmpty)
    }

    func testAttachedSheetPageTextIsJoinedAndCapped() {
        let pages = ["First problem.", "", "Second problem uses Lemma 2.1."]
        XCTAssertEqual(
            AskAttachmentExtractor.combinePageTexts(pages),
            "First problem.\n\nSecond problem uses Lemma 2.1."
        )

        let huge = [String(repeating: "x", count: AskPromptBuilder.storedSheetCharacters + 50)]
        XCTAssertEqual(
            AskAttachmentExtractor.combinePageTexts(huge).count,
            AskPromptBuilder.storedSheetCharacters
        )
    }
}
