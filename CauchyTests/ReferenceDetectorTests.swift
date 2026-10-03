import XCTest
@testable import Cauchy

final class ReferenceDetectorTests: XCTestCase {
    func testNamedBlockReference() {
        let reference = ReferenceDetector.firstReference(in: "see Theorem 1.2 for details")
        XCTAssertEqual(reference?.kind, .theorem)
        XCTAssertEqual(reference?.number, "1.2")
    }

    func testLemmaReference() {
        let reference = ReferenceDetector.firstReference(in: "By Lemma 3.4 we obtain")
        XCTAssertEqual(reference?.kind, .lemma)
        XCTAssertEqual(reference?.number, "3.4")
    }

    func testAppendixReference() {
        let reference = ReferenceDetector.firstReference(in: "Remark A.0.5. This is an appendix statement.")
        XCTAssertEqual(reference?.kind, .remark)
        XCTAssertEqual(reference?.number, "A.0.5")
    }

    func testEquationCiteByParenthetical() {
        let reference = ReferenceDetector.firstReference(in: "as shown by (1.2)")
        XCTAssertEqual(reference?.kind, .equation)
        XCTAssertEqual(reference?.number, "1.2")
    }

    func testEquationCiteWithPrefix() {
        let reference = ReferenceDetector.firstReference(in: "from Eq. (2.3) it follows")
        XCTAssertEqual(reference?.kind, .equation)
        XCTAssertEqual(reference?.number, "2.3")
    }

    func testFigurePanelMentionResolvesToNumberedFigure() {
        let reference = ReferenceDetector.firstReference(in: "See Fig. 3a,b for the comparison.")
        XCTAssertEqual(reference, DetectedReference(kind: .figure, number: "3"))
    }

    func testFigureCaptionAndFullWordMentionShareIdentity() {
        let references = ReferenceDetector.allReferences(in: "Fig. 2 | Results. Later, Figure 2a shows the trend.")
        XCTAssertEqual(references.map(\.reference), [
            DetectedReference(kind: .figure, number: "2"),
            DetectedReference(kind: .figure, number: "2")
        ])
    }

    func testPairedPluralFigureCitationCreatesTwoAnchors() {
        let text = "Figures 1e and 3a,b show the result."
        let matches = ReferenceDetector.allReferences(in: text)
        XCTAssertEqual(matches.map(\.reference), [
            DetectedReference(kind: .figure, number: "1"),
            DetectedReference(kind: .figure, number: "3")
        ])
        XCTAssertEqual(matches.map { String(text[$0.range]) }, ["Figures 1e", "3a,b"])
    }

    func testBestReferencePrefersCursorPosition() {
        let text = "Theorem 1.1 and (1.2)"
        let theoremOffset = text.distance(from: text.startIndex, to: text.range(of: "Theorem")!.lowerBound)
        let equationOffset = text.distance(from: text.startIndex, to: text.range(of: "(1.2)")!.lowerBound) + 1

        XCTAssertEqual(ReferenceDetector.bestReference(in: text, cursorOffset: theoremOffset)?.kind, .theorem)
        XCTAssertEqual(ReferenceDetector.bestReference(in: text, cursorOffset: equationOffset)?.kind, .equation)
    }

    func testNoReferenceInPlainText() {
        XCTAssertNil(ReferenceDetector.firstReference(in: "This is ordinary text."))
    }
}
