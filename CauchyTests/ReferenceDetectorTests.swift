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

    func testCursorOffsetIsUTF16SoAGlyphBeforeTheCitationDoesNotShiftIt() {
        let text = "😀 [IK99, Lemma 1.15] and Lemma 2.1."
        let utf16 = (text as NSString).range(of: "Lemma 1.15").location
        let characters = text.distance(from: text.startIndex, to: text.range(of: "Lemma 1.15")!.lowerBound)
        XCTAssertNotEqual(utf16, characters)
        XCTAssertNil(ReferenceDetector.bestReference(in: text, cursorOffset: utf16))
        XCTAssertEqual(ReferenceDetector.externalCitation(in: text, cursorOffset: utf16)?.key, "IK99")

        let local = (text as NSString).range(of: "Lemma 2.1").location
        XCTAssertEqual(
            ReferenceDetector.bestReference(in: text, cursorOffset: local),
            DetectedReference(kind: .lemma, number: "2.1")
        )
    }

    func testPluralListsResolveEachNumber() {
        let single = ReferenceDetector.allReferences(in: "Lemmas 4.6 and the rest.")
        XCTAssertEqual(single.map(\.reference), [DetectedReference(kind: .lemma, number: "4.6")])

        let definitions = ReferenceDetector.allReferences(in: "Definitions 2.5 follow.")
        XCTAssertEqual(definitions.map(\.reference), [DetectedReference(kind: .definition, number: "2.5")])

        let text = "Lemmas 3.1, 3.2 and 3.4"
        let matches = ReferenceDetector.allReferences(in: text)
        XCTAssertEqual(matches.map(\.reference.number), ["3.1", "3.2", "3.4"])
        XCTAssertEqual(matches.map { String(text[$0.range]) }, ["Lemmas 3.1", "3.2", "3.4"])

        XCTAssertNil(ReferenceDetector.firstReference(in: "Thm. 3.2 is abbreviated."))
    }

    func testParenthesizedStatementNumberIsNotAnEquation() {
        let text = "Theorem (3.2) gives the bound used in (3.1)."
        let matches = ReferenceDetector.allReferences(in: text)
        XCTAssertEqual(matches.map(\.reference), [
            DetectedReference(kind: .theorem, number: "3.2"),
            DetectedReference(kind: .equation, number: "3.1"),
        ])
        XCTAssertEqual(matches.map { String(text[$0.range]) }, ["Theorem (3.2)", "(3.1)"])

        let inside = (text as NSString).range(of: "(3.2)").location + 1
        XCTAssertEqual(
            ReferenceDetector.bestReference(in: text, cursorOffset: inside),
            DetectedReference(kind: .theorem, number: "3.2")
        )
        XCTAssertEqual(
            ReferenceDetector.firstReference(in: "Definition (2.5) names the term."),
            DetectedReference(kind: .definition, number: "2.5")
        )
        XCTAssertNil(ReferenceDetector.firstReference(in: "By [12, Theorem (3.2)] the map is continuous."))
        XCTAssertEqual(
            ReferenceDetector.firstReference(in: "from Eq. (2.3) it follows")?.kind,
            .equation
        )
        XCTAssertEqual(
            ReferenceDetector.firstReference(in: "as shown by (1.2)")?.kind,
            .equation
        )
    }

    func testNoReferenceInPlainText() {
        XCTAssertNil(ReferenceDetector.firstReference(in: "This is ordinary text."))
    }

    func testAuthorYearBracketIsNotALocalLemma() {
        let text = "We refer the reader to [IK99, Lemma 1.15] for a proof. Lemma 2.1."
        let references = ReferenceDetector.allReferences(in: text)
        XCTAssertEqual(references.map(\.reference), [
            DetectedReference(kind: .lemma, number: "2.1")
        ])

        let inside = text.distance(from: text.startIndex, to: text.range(of: "Lemma 1.15")!.lowerBound)
        XCTAssertNil(ReferenceDetector.bestReference(in: text, cursorOffset: inside))
        let citation = ReferenceDetector.externalCitation(in: text, cursorOffset: inside)
        XCTAssertEqual(citation?.key, "IK99")
        XCTAssertEqual(citation?.qualifier, "Lemma 1.15")
        XCTAssertNil(citation?.author)

        let local = text.distance(from: text.startIndex, to: text.range(of: "Lemma 2.1")!.lowerBound)
        XCTAssertEqual(
            ReferenceDetector.bestReference(in: text, cursorOffset: local),
            DetectedReference(kind: .lemma, number: "2.1")
        )
        XCTAssertNil(ReferenceDetector.externalCitation(in: text, cursorOffset: local))
    }

    func testCitationBracketSplitAcrossALineIsNotALocalTheorem() {
        let text = "the weak-holomorphy criterion [17,\nTheorem 3.31(c)] shows that G is analytic."
        XCTAssertTrue(ReferenceDetector.allReferences(in: text).isEmpty)
        let offset = text.distance(from: text.startIndex, to: text.range(of: "Theorem")!.lowerBound)
        let citation = ReferenceDetector.externalCitation(in: text, cursorOffset: offset)
        XCTAssertEqual(citation?.key, "17")
        XCTAssertEqual(citation?.qualifier, "Theorem 3.31(c)")
        XCTAssertNil(ReferenceDetector.bestReference(in: text, cursorOffset: offset))
    }

    func testNumericBracketCitationIsNotALocalTheorem() {
        let text = "By [12, Theorem 3.2] the map is continuous."
        XCTAssertTrue(ReferenceDetector.allReferences(in: text).isEmpty)
        let offset = text.distance(from: text.startIndex, to: text.range(of: "12")!.lowerBound)
        let citation = ReferenceDetector.externalCitation(in: text, cursorOffset: offset)
        XCTAssertEqual(citation?.key, "12")
        XCTAssertEqual(citation?.qualifier, "Theorem 3.2")
    }

    func testPlainBracketAndAuthorYearForms() {
        let numbered = "See [12] for the construction."
        let numberedOffset = numbered.distance(from: numbered.startIndex, to: numbered.range(of: "[12]")!.lowerBound) + 1
        XCTAssertEqual(ReferenceDetector.externalCitation(in: numbered, cursorOffset: numberedOffset)?.key, "12")
        XCTAssertNil(ReferenceDetector.externalCitation(in: numbered, cursorOffset: numberedOffset)?.qualifier)

        let parenthetical = "The estimate is due to (Smith 2019)."
        let nameOffset = parenthetical.distance(from: parenthetical.startIndex, to: parenthetical.range(of: "Smith")!.lowerBound)
        let cited = ReferenceDetector.externalCitation(in: parenthetical, cursorOffset: nameOffset)
        XCTAssertEqual(cited?.author, "Smith")
        XCTAssertEqual(cited?.year, "2019")
        XCTAssertNil(cited?.key)

        let bracketYear = "Smith et al. [2019] proved the bound."
        let etAl = bracketYear.distance(from: bracketYear.startIndex, to: bracketYear.range(of: "2019")!.lowerBound)
        let yearCite = ReferenceDetector.externalCitation(in: bracketYear, cursorOffset: etAl)
        XCTAssertEqual(yearCite?.author, "Smith")
        XCTAssertEqual(yearCite?.year, "2019")
    }

    func testIntervalIsNotACitation() {
        let text = "The interval [0, 1] contains the origin."
        XCTAssertNil(ReferenceDetector.externalCitation(in: text, cursorOffset: text.count / 2))
        XCTAssertTrue(ReferenceDetector.allReferences(in: "Consider the range [1, 2, 3] next.").isEmpty)
    }

    func testDisambiguatedKeyAndEquationQualifierAreCitations() {
        let named = "By [BO09b, Lemma 3.3], the perturbation is small. Lemma 2.1."
        XCTAssertEqual(
            ReferenceDetector.allReferences(in: named).map(\.reference),
            [DetectedReference(kind: .lemma, number: "2.1")]
        )
        let namedOffset = named.distance(from: named.startIndex, to: named.range(of: "Lemma 3.3")!.lowerBound)
        XCTAssertEqual(ReferenceDetector.externalCitation(in: named, cursorOffset: namedOffset)?.key, "BO09b")
        XCTAssertNil(ReferenceDetector.bestReference(in: named, cursorOffset: namedOffset))

        let equation = "Thus wn(t) ∈ Rbσ = M [3, (1.3)]. Since d is faithful."
        XCTAssertTrue(ReferenceDetector.allReferences(in: equation).isEmpty)
        let equationOffset = equation.distance(from: equation.startIndex, to: equation.range(of: "(1.3)")!.lowerBound)
        XCTAssertEqual(ReferenceDetector.externalCitation(in: equation, cursorOffset: equationOffset)?.key, "3")
        XCTAssertEqual(ReferenceDetector.externalCitation(in: equation, cursorOffset: equationOffset)?.qualifier, "(1.3)")
    }

    func testHoverShowsTheBibliographyEntryOrNothing() {
        let paper = """
        1. Introduction
        See [IK99, Lemma 1.15], See [12], and (Smith 2019).

        References
        [IK99] I. Khasin and K. Author, Sums of powers, Adv. Math. 12 (1999), 1–10.
        [12] A. Baker, Another paper, Journal 3 (2010), 4–8.
        Smith, J. (2019). Compact generation. Algebra & Number Theory.
        Smith, A. (2019). A different paper. Annals.
        """
        let entries = BibliographyIndex.entries(in: paper)
        let lemmaOffset = paper.distance(from: paper.startIndex, to: paper.range(of: "Lemma 1.15")!.lowerBound)
        let citation = ReferenceDetector.externalCitation(in: paper, cursorOffset: lemmaOffset)!
        XCTAssertEqual(
            BibliographyIndex.hoverText(for: citation, in: entries),
            "Sums of powers\nI. Khasin and K. Author, 1999\nLemma 1.15 in the cited paper"
        )

        let plain = paper.distance(from: paper.startIndex, to: paper.range(of: "See [12]")!.lowerBound) + 5
        let numbered = ReferenceDetector.externalCitation(in: paper, cursorOffset: plain)!
        XCTAssertEqual(
            BibliographyIndex.hoverText(for: numbered, in: entries),
            "Another paper\nA. Baker, 2010"
        )

        let smithOffset = paper.distance(from: paper.startIndex, to: paper.range(of: "Smith 2019")!.lowerBound)
        let smith = ReferenceDetector.externalCitation(in: paper, cursorOffset: smithOffset)!
        XCTAssertNil(BibliographyIndex.hoverText(for: smith, in: entries))

        let missing = ExternalCitation(key: "ZZ99", author: nil, year: nil, qualifier: "Lemma 1", range: paper.startIndex..<paper.startIndex)
        XCTAssertNil(BibliographyIndex.hoverText(for: missing, in: entries))
    }

    func testQuotedBibliographyTitleLeadsTheHover() {
        let paper = """
        See [QR23, Lemma 2.1] and [AB19, Theorem 1].

        References
        [QR23]
        Q. Quinn, R. Rivera, and S. Santos. “Synthetic tensor categories
        in a sample ring”. In: Example Math. 4 (2023), pp. 10–20.
        [AB19] A. Abel, B. Baker, and C. Chen. A short note on sample rings. Sample J. 1 (2019), 1–10.
        """
        let entries = BibliographyIndex.entries(in: paper)
        let quoted = entries.first { $0.key == "QR23" }
        XCTAssertEqual(quoted?.authors, "Q. Quinn, R. Rivera, and S. Santos")
        XCTAssertEqual(quoted?.title, "Synthetic tensor categories in a sample ring")
        XCTAssertEqual(quoted?.year, "2023")

        let lemmaOffset = paper.distance(from: paper.startIndex, to: paper.range(of: "Lemma 2.1")!.lowerBound)
        let citation = ReferenceDetector.externalCitation(in: paper, cursorOffset: lemmaOffset)!
        XCTAssertEqual(
            BibliographyIndex.hoverText(for: citation, in: entries),
            "Synthetic tensor categories in a sample ring\nQ. Quinn, R. Rivera, and S. Santos, 2023\nLemma 2.1 in the cited paper"
        )

        let oxford = entries.first { $0.key == "AB19" }
        XCTAssertEqual(oxford?.authors, "A. Abel, B. Baker, and C. Chen")
        XCTAssertEqual(oxford?.title, "A short note on sample rings")
        XCTAssertEqual(oxford?.year, "2019")
    }
}
