import XCTest
@testable import Cauchy

/// The prompt is what keeps narration out. The filter only cuts a meta
/// clause, and it must not throw away a formula that shared the sentence.
final class AnswerVoiceTests: XCTestCase {
    func testMetaClauseIsRemovedAndTheFormulaInThatSentenceStays() {
        let raw = "The formula is written as B(z0,r)\\{0} in the extracted text, likely a typo or extraction artifact. The integral is over the punctured disc B(z0, r) excluding 0."
        let shaped = AnswerVoice.shape(raw)

        XCTAssertTrue(shaped.contains("B(z0,r)\\{0}"))
        XCTAssertTrue(shaped.contains("punctured disc"))
        XCTAssertFalse(AnswerVoice.containsBannedMeta(shaped))
        XCTAssertFalse(shaped.localizedCaseInsensitiveContains("extracted text"))
        XCTAssertFalse(shaped.localizedCaseInsensitiveContains("extraction artifact"))
    }

    func testASentenceThatIsOnlyNarrationGoesAndTheMathematicsStays() {
        let raw = "The selected passage makes two consecutive deductions. Because h(z₀) = h′(z₀) = 0, the first two Taylor coefficients vanish, so a₀ = a₁ = 0. Separating what appears in the supplied excerpts from standard facts, this is the usual vanishing of the constant and linear terms."
        let shaped = AnswerVoice.shape(raw)

        XCTAssertFalse(shaped.localizedCaseInsensitiveContains("selected passage"))
        XCTAssertFalse(shaped.localizedCaseInsensitiveContains("supplied excerpt"))
        XCTAssertTrue(shaped.contains("Because h(z₀) = h′(z₀) = 0"))
        XCTAssertTrue(shaped.contains("a₀ = a₁ = 0"))
        XCTAssertTrue(shaped.localizedCaseInsensitiveContains("usual vanishing"))
    }

    func testCheckTheOriginalPageIsAClauseAndTheCitationStays() {
        let raw = "The sum is written without the summation symbol, so check the original page. It equals n(n+1)/2. [S1]"
        let shaped = AnswerVoice.shape(raw)

        XCTAssertTrue(shaped.contains("without the summation symbol"))
        XCTAssertTrue(shaped.contains("n(n+1)/2"))
        XCTAssertTrue(shaped.contains("[S1]"))
        XCTAssertFalse(shaped.localizedCaseInsensitiveContains("check the original page"))
    }

    func testAMarkerOnADroppedNarrationSentenceIsKept() {
        let raw = "The selected passage is the whole claim [S1]. Because a0 = 0, the constant term vanishes."
        let shaped = AnswerVoice.shape(raw)

        XCTAssertFalse(shaped.localizedCaseInsensitiveContains("selected passage"))
        XCTAssertTrue(shaped.contains("a0 = 0"))
        XCTAssertTrue(shaped.contains("[S1]"))
    }

    func testInstructionsTellTheModelToOpenWithTheMathematics() {
        let prompt = ReadingPromptBuilder.instructions(
            for: ReadingContext(
                documentTitle: "Synthetic Notes",
                selectedText: "since h(z0) = h'(z0) = 0 we see a0 = a1 = 0",
                surroundingText: "nearby lines",
                retrievedPassages: []
            ),
            provider: .claudeCode
        )
        XCTAssertTrue(prompt.contains("first sentence"))
        XCTAssertTrue(prompt.contains("professor"))
        XCTAssertTrue(prompt.contains("extracted text"))
        XCTAssertTrue(prompt.contains("check the original page"))
        XCTAssertTrue(prompt.contains("since h(z0) = h'(z0) = 0 we see a0 = a1 = 0"))
        XCTAssertTrue(prompt.contains("definition or result"))
        XCTAssertFalse(prompt.contains("Because $h(z_0)"))
        XCTAssertFalse(prompt.contains("first two Taylor coefficients vanish"))
        XCTAssertFalse(prompt.contains("Say when a precise formula needs checking"))
        XCTAssertFalse(prompt.contains("PDF SOURCE EXCERPTS"))
    }

    /// The instruction text is general. Topic words from one paper, or from
    /// the three questions used to check this prompt, must not be written
    /// into the rules. The lines the reader selected are a different matter:
    /// this fixture contains none of them, so a hit is the template itself.
    func testInstructionsDoNotNameTopicsFromOnePaper() {
        let prompt = ReadingPromptBuilder.instructions(
            for: ReadingContext(
                documentTitle: "Notes",
                selectedText: "The lemma applies.",
                surroundingText: "A nearby remark.",
                retrievedPassages: []
            ),
            provider: .claudeCode
        )
        let lowered = prompt.lowercased()
        let topicWords = [
            "taylor",
            "connected",
            "integral",
            "h(z",
            "compact",
            "order at least 2",
        ]
        for word in topicWords {
            XCTAssertFalse(lowered.contains(word), "instructions name \(word)")
        }
    }

    /// The worked example used to be the Taylor sentence. A later question
    /// about a different highlight then opened with that sentence. The
    /// selected lines stay in the prompt; the instructions do not supply an
    /// answer from some other selection.
    func testInstructionsDoNotPlantAnAnswerFromAnotherSelection() {
        let selected = "Proposition 5.3. A continuous image of a closed interval is connected."
        let prompt = ReadingPromptBuilder.instructions(
            for: ReadingContext(
                documentTitle: "Synthetic notes on a holomorphic function",
                selectedText: selected,
                surroundingText: "Since h(z0)=h'(z0)=0 we see a0=a1=0, hence the sum starts at k>=2.",
                retrievedPassages: []
            ),
            provider: .claudeCode
        )

        let sections = prompt.components(separatedBy: "---")
        XCTAssertGreaterThanOrEqual(sections.count, 2)
        let asked = sections[1]
        XCTAssertTrue(asked.contains(selected))
        XCTAssertFalse(asked.contains("h(z0)"))
        XCTAssertFalse(prompt.contains("Because $h(z_0)"))
        XCTAssertFalse(prompt.contains("first two Taylor coefficients vanish"))
        XCTAssertTrue(prompt.contains("the lines they asked about"))
    }
}
