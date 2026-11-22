import XCTest
@testable import Cauchy

/// Three synthetic replies. The model narrates the pipeline; the reader sees
/// the mathematics, and a citation on a dropped sentence is kept.
final class AnswerVoiceTests: XCTestCase {
    func testTutorVoiceDropsPipelineNarrationAndKeepsTheMathematics() {
        let cases: [(before: String, after: String)] = [
            (
                """
                The selected passage makes two consecutive deductions. Because h(z₀) = h′(z₀) = 0, the first two Taylor coefficients vanish, so a₀ = a₁ = 0. Separating what appears in the supplied excerpts from standard facts, this is the usual vanishing of the constant and linear terms.
                """,
                "Because h(z₀) = h′(z₀) = 0, the first two Taylor coefficients vanish, so a₀ = a₁ = 0."
            ),
            (
                "The formula is written as B(z0,r)\\{0} in the extracted text, likely a typo or extraction artifact. The integral is over the punctured disc B(z0, r) excluding 0.",
                "The integral is over the punctured disc B(z0, r) excluding 0."
            ),
            (
                "The sum is written without the summation symbol, so check the original page. It equals n(n+1)/2. [S1]",
                "It equals n(n+1)/2. [S1]"
            ),
        ]

        for sample in cases {
            let shaped = AnswerVoice.shape(sample.before)
            XCTAssertEqual(shaped, sample.after)
            XCTAssertFalse(AnswerVoice.containsBannedMeta(shaped))
            XCTAssertTrue(AnswerVoice.containsBannedMeta(sample.before))
        }
    }

    func testATaylorConclusionDoesNotSuggestNearbyPropositions() {
        let nearby = [
            ReaderFollowUpStatement(
                reference: DetectedReference(kind: .proposition, number: "1.4.14"),
                pageIndex: 81,
                statementText: "A holomorphic function with a zero derivative is constant."
            ),
            ReaderFollowUpStatement(
                reference: DetectedReference(kind: .proposition, number: "1.5.8"),
                pageIndex: 89,
                statementText: "The zeros of a non-zero holomorphic function are isolated."
            ),
        ]
        let answer = AnswerVoice.shape(
            "The selected passage makes two consecutive deductions. Because h(z₀) = h′(z₀) = 0, the first two Taylor coefficients vanish, so a₀ = a₁ = 0."
        )
        let chips = ReaderFollowUps.suggest(
            answer: answer,
            question: "slightly lost how we concluded this",
            selection: "Suppose h(z0) = h'(z0) = 0. Then a0 = a1 = 0.",
            statements: nearby
        )
        XCTAssertTrue(chips.isEmpty)
    }
}
