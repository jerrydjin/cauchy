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

    func testBibliographyQualifiedCitationStaysUnlinked() {
        let cited = "[12, Theorem 3.2]"
        XCTAssertNil(ReferenceDetector.firstReference(in: cited))
        XCTAssertTrue(ReferenceDetector.allReferences(in: cited).isEmpty)
        let theoremOffset = cited.distance(from: cited.startIndex, to: cited.range(of: "Theorem")!.lowerBound)
        XCTAssertNil(ReferenceDetector.bestReference(in: cited, cursorOffset: theoremOffset))

        XCTAssertNil(ReferenceDetector.firstReference(in: "[12, Thm. 3.2]"))
        XCTAssertTrue(ReferenceDetector.allReferences(in: "[12, Theorems 2.1 and 2.3]").isEmpty)
        XCTAssertNil(ReferenceDetector.firstReference(in: "[see 12, Theorem 3.2]"))
        XCTAssertNil(ReferenceDetector.firstReference(in: "[12-14, Theorem 3.2]"))
    }

    func testPlainTheoremStillResolves() {
        let reference = ReferenceDetector.firstReference(in: "Theorem 3.2")
        XCTAssertEqual(reference, DetectedReference(kind: .theorem, number: "3.2"))

        let text = "see Theorem 3.2 for the bound"
        let offset = text.distance(from: text.startIndex, to: text.range(of: "Theorem")!.lowerBound)
        XCTAssertEqual(
            ReferenceDetector.bestReference(in: text, cursorOffset: offset),
            DetectedReference(kind: .theorem, number: "3.2")
        )
    }

    func testLocalTheoremBesideBibliographyCitationStillResolves() {
        let text = "Theorem 3.2 improves the bound in [12, Theorem 3.2]."
        let matches = ReferenceDetector.allReferences(in: text)
        XCTAssertEqual(matches.map(\.reference), [
            DetectedReference(kind: .theorem, number: "3.2")
        ])
        XCTAssertEqual(matches.map { String(text[$0.range]) }, ["Theorem 3.2"])

        let localOffset = text.distance(from: text.startIndex, to: text.range(of: "Theorem 3.2")!.lowerBound)
        XCTAssertEqual(
            ReferenceDetector.bestReference(in: text, cursorOffset: localOffset),
            DetectedReference(kind: .theorem, number: "3.2")
        )

        let cited = text.range(of: "[12, Theorem 3.2]")!
        let citedTheorem = text.range(of: "Theorem", range: cited)!
        let citedOffset = text.distance(from: text.startIndex, to: citedTheorem.lowerBound)
        XCTAssertNil(ReferenceDetector.bestReference(in: text, cursorOffset: citedOffset))
        let bracketOffset = text.distance(from: text.startIndex, to: cited.lowerBound)
        XCTAssertNil(ReferenceDetector.bestReference(in: text, cursorOffset: bracketOffset))
    }

    func testAbbreviationsResolveLikeTheFullWord() {
        let pairs = [
            ("Thm. 3.2", "Theorem 3.2"),
            ("Thm 3.2", "Theorem 3.2"),
            ("Prop. 4.1", "Proposition 4.1"),
            ("Lem. 3.4", "Lemma 3.4"),
            ("Cor. 2.2", "Corollary 2.2"),
            ("Def. 5", "Definition 5"),
            ("Eq. (2.3)", "Equation (2.3)"),
            ("Eq (2.3)", "Equation (2.3)"),
            ("Fig. 3", "Figure 3"),
            ("Fig 3", "Figure 3"),
        ]
        for (abbreviated, full) in pairs {
            let resolved = ReferenceDetector.firstReference(in: abbreviated)
            XCTAssertNotNil(resolved, abbreviated)
            XCTAssertEqual(resolved, ReferenceDetector.firstReference(in: full), abbreviated)
        }
    }

    func testPluralTheoremListResolvesEachNumber() {
        let text = "Theorems 2.1 and 2.3"
        let matches = ReferenceDetector.allReferences(in: text)
        XCTAssertEqual(matches.map(\.reference), [
            DetectedReference(kind: .theorem, number: "2.1"),
            DetectedReference(kind: .theorem, number: "2.3"),
        ])
        XCTAssertEqual(matches.map { String(text[$0.range]) }, ["Theorems 2.1", "2.3"])

        let firstOffset = text.distance(from: text.startIndex, to: text.range(of: "2.1")!.lowerBound)
        let secondOffset = text.distance(from: text.startIndex, to: text.range(of: "2.3")!.lowerBound)
        XCTAssertEqual(
            ReferenceDetector.bestReference(in: text, cursorOffset: firstOffset),
            DetectedReference(kind: .theorem, number: "2.1")
        )
        XCTAssertEqual(
            ReferenceDetector.bestReference(in: text, cursorOffset: secondOffset),
            DetectedReference(kind: .theorem, number: "2.3")
        )
    }

    func testPluralLemmaListResolvesEachNumber() {
        for text in ["Lemmas 3.1, 3.2 and 3.4", "Lemmas 3.1, 3.2, and 3.4"] {
            let matches = ReferenceDetector.allReferences(in: text)
            XCTAssertEqual(matches.map(\.reference), [
                DetectedReference(kind: .lemma, number: "3.1"),
                DetectedReference(kind: .lemma, number: "3.2"),
                DetectedReference(kind: .lemma, number: "3.4"),
            ], text)
            XCTAssertEqual(matches.map { String(text[$0.range]) }, ["Lemmas 3.1", "3.2", "3.4"], text)
        }
    }

    func testPluralTheoremRangeResolvesEachEndpoint() {
        for text in ["Theorems 2.1–2.3", "Theorems 2.1-2.3"] {
            let matches = ReferenceDetector.allReferences(in: text)
            XCTAssertEqual(matches.map(\.reference), [
                DetectedReference(kind: .theorem, number: "2.1"),
                DetectedReference(kind: .theorem, number: "2.3"),
            ], text)
            XCTAssertEqual(matches.map { String(text[$0.range]) }, ["Theorems 2.1", "2.3"], text)

            let firstOffset = text.distance(from: text.startIndex, to: text.range(of: "2.1")!.lowerBound)
            let secondOffset = text.distance(from: text.startIndex, to: text.range(of: "2.3")!.lowerBound)
            XCTAssertEqual(
                ReferenceDetector.bestReference(in: text, cursorOffset: firstOffset),
                DetectedReference(kind: .theorem, number: "2.1"),
                text
            )
            XCTAssertEqual(
                ReferenceDetector.bestReference(in: text, cursorOffset: secondOffset),
                DetectedReference(kind: .theorem, number: "2.3"),
                text
            )
        }
    }
}
