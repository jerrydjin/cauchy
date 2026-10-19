import XCTest
@testable import Cauchy

final class AskStructureLocatorTests: XCTestCase {
    func testTopLevelNumberedTitleIsThatSection() {
        let structure = paper
        let section1 = AskStructureLocator.query(in: "what is section 1 about")
        XCTAssertEqual(section1?.canonical, "1")
        guard case .found(let span) = AskStructureLocator.locate(section1!, in: structure) else {
            return XCTFail("Expected section 1")
        }
        XCTAssertEqual(span.startPage, 0)

        let section3 = AskStructureLocator.query(in: "what is section 3 about")!
        guard case .found(let later) = AskStructureLocator.locate(section3, in: structure) else {
            return XCTFail("Expected section 3")
        }
        XCTAssertEqual(later.startPage, 13)
    }

    func testDottedHeadingWithAClosingPeriodIsThatSubsection() {
        let query = AskStructureLocator.query(in: "what is section 3.1 about")!
        guard case .found(let span) = AskStructureLocator.locate(query, in: paper) else {
            return XCTFail("Expected section 3.1")
        }
        XCTAssertEqual(span.startPage, 14)
    }

    func testDottedHeadingDoesNotSatisfyAnUndottedSectionQuery() {
        let query = AskStructureLocator.query(in: "what is section 2 about")!
        guard case .found(let span) = AskStructureLocator.locate(query, in: paper) else {
            return XCTFail("Expected section 2")
        }
        XCTAssertEqual(span.startPage, 1)
    }

    func testNumberedSentenceIsNotASectionHeading() {
        let structure = AskDocumentStructure(
            outline: [],
            pages: [
                AskPageSnapshot(pageIndex: 2, text: "2 Integrals appear here."),
                AskPageSnapshot(
                    pageIndex: 12,
                    text: "2. Groups\nGroups begin with a definition long enough to keep."
                ),
            ],
            pageCount: 20
        )
        let query = AskStructureLocator.query(in: "what is section 2 about")!
        guard case .found(let span) = AskStructureLocator.locate(query, in: structure) else {
            return XCTFail("Expected the printed section heading")
        }
        XCTAssertEqual(span.startPage, 12)
    }

    func testMathFragmentIsNotASectionHeading() {
        let structure = AskDocumentStructure(
            outline: [],
            pages: [
                AskPageSnapshot(pageIndex: 3, text: "1 + w holds over a prime field. Hence the relation is strict."),
                AskPageSnapshot(pageIndex: 4, text: "Section 4 constructs the approximate metric and solves the nonlinear equation."),
                AskPageSnapshot(pageIndex: 4, text: "4 be the"),
                AskPageSnapshot(pageIndex: 8, text: "1. Introduction\nThe algebra is introduced here and used below."),
                AskPageSnapshot(pageIndex: 10, text: "4. Block-sum\nThe sum is defined here."),
            ],
            pageCount: 20
        )
        let section1 = AskStructureLocator.query(in: "what is section 1 about")!
        guard case .found(let first) = AskStructureLocator.locate(section1, in: structure) else {
            return XCTFail("Expected section 1")
        }
        XCTAssertEqual(first.startPage, 8)
        let section4 = AskStructureLocator.query(in: "what is section 4 about")!
        guard case .found(let later) = AskStructureLocator.locate(section4, in: structure) else {
            return XCTFail("Expected section 4")
        }
        XCTAssertEqual(later.startPage, 10)
    }

    func testUnnumberedOutlineBookmarksAreSectionsInOrder() {
        let structure = AskDocumentStructure(
            outline: [
                AskOutlineNode(title: "Introduction", pageIndex: 0, children: []),
                AskOutlineNode(title: "Preliminaries", pageIndex: 2, children: [
                    AskOutlineNode(title: "Generator notation", pageIndex: 2, children: []),
                ]),
                AskOutlineNode(title: "Proof of the main result", pageIndex: 5, children: [
                    AskOutlineNode(title: "Low degree subspaces", pageIndex: 5, children: []),
                ]),
                AskOutlineNode(title: "References", pageIndex: 12, children: []),
            ],
            pages: [],
            pageCount: 16
        )
        let section1 = AskStructureLocator.query(in: "what is section 1 about")!
        guard case .found(let first) = AskStructureLocator.locate(section1, in: structure) else {
            return XCTFail("Expected section 1")
        }
        XCTAssertEqual(first.startPage, 0)
        let section3 = AskStructureLocator.query(in: "what is section 3.1 about")!
        guard case .found(let nested) = AskStructureLocator.locate(section3, in: structure) else {
            return XCTFail("Expected section 3.1")
        }
        XCTAssertEqual(nested.startPage, 5)
    }

    func testNumberedSiblingKeepsItsNumberBesideIntroduction() {
        let structure = AskDocumentStructure(
            outline: [
                AskOutlineNode(title: "Introduction", pageIndex: 0, children: []),
                AskOutlineNode(title: "1. Preliminaries", pageIndex: 4, children: []),
                AskOutlineNode(title: "2. Linear models", pageIndex: 8, children: []),
            ],
            pages: [],
            pageCount: 20
        )
        let section1 = AskStructureLocator.query(in: "what is section 1 about")!
        guard case .found(let first) = AskStructureLocator.locate(section1, in: structure) else {
            return XCTFail("Expected the numbered preliminaries")
        }
        XCTAssertEqual(first.startPage, 4)
    }

    func testOutlineNumberedTitleMatchesTheSameSection() {
        let structure = AskDocumentStructure(
            outline: [
                AskOutlineNode(title: "1. Introduction", pageIndex: 0, children: []),
                AskOutlineNode(title: "2. Preliminaries", pageIndex: 4, children: [
                    AskOutlineNode(title: "2.1 Generalities", pageIndex: 4, children: []),
                ]),
            ],
            pages: [],
            pageCount: 20
        )
        let query = AskStructureLocator.query(in: "what is section 1 about")!
        guard case .found(let span) = AskStructureLocator.locate(query, in: structure) else {
            return XCTFail("Expected the outline heading")
        }
        XCTAssertEqual(span.startPage, 0)
        XCTAssertEqual(span.endPage, 4)
    }

    func testBoldSectionNumberOnItsOwnLineKeepsTheTitle() {
        let structure = AskDocumentStructure(
            outline: [],
            pages: [
                AskPageSnapshot(
                    pageIndex: 2,
                    text: "1.\nIntroduction\nThe argument starts here and is not a heading.",
                    lineBold: [true, true, false]
                ),
            ],
            pageCount: 4
        )
        let query = AskStructureLocator.query(in: "what is section 1 about")!
        guard case .found(let span) = AskStructureLocator.locate(query, in: structure) else {
            return XCTFail("Expected the split heading")
        }
        XCTAssertEqual(span.startPage, 2)
        XCTAssertTrue(span.label.contains("Introduction"))
    }

    func testItalicSubsectionNumberOnItsOwnLineKeepsTheTitle() {
        let structure = AskDocumentStructure(
            outline: [],
            pages: [
                AskPageSnapshot(
                    pageIndex: 4,
                    text: "3.2.\nData assimilation strategy\nThe filter is derived in the following paragraphs.",
                    lineBold: [false, false, false],
                    lineItalic: [true, true, false]
                ),
            ],
            pageCount: 6
        )
        let query = AskStructureLocator.query(in: "what is section 3.2 about")!
        guard case .found(let span) = AskStructureLocator.locate(query, in: structure) else {
            return XCTFail("Expected the italic subsection")
        }
        XCTAssertEqual(span.startPage, 4)
        XCTAssertTrue(span.label.contains("assimilation"))
    }

    func testNumberedStepOnItsOwnLineIsNotAHeading() {
        let structure = AskDocumentStructure(
            outline: [],
            pages: [
                AskPageSnapshot(
                    pageIndex: 1,
                    text: "3.\nFix an isomorphism of the underlying bundle\nMore prose follows.",
                    lineBold: [false, false, false]
                ),
            ],
            pageCount: 3
        )
        let query = AskStructureLocator.query(in: "what is section 3 about")!
        if case .found = AskStructureLocator.locate(query, in: structure) {
            XCTFail("An ordinary numbered step is not a section heading")
        }
    }

    func testRunInHeadingKeepsTheTitleAndDropsTheParagraph() {
        let structure = AskDocumentStructure(
            outline: [],
            pages: [
                AskPageSnapshot(
                    pageIndex: 4,
                    text: "2.4. Small cases. Let G be a graph with four vertices and one cycle.\nThe rest of the page is ordinary prose about matrices."
                ),
            ],
            pageCount: 8
        )
        let query = AskStructureLocator.query(in: "what is section 2.4 about")!
        guard case .found(let span) = AskStructureLocator.locate(query, in: structure) else {
            return XCTFail("Expected the run-in heading")
        }
        XCTAssertEqual(span.startPage, 4)
        XCTAssertTrue(span.label.contains("Small cases"))
        XCTAssertFalse(span.label.lowercased().contains("graph"))
    }

    func testNumberedProofSentenceIsNotARunInHeading() {
        let structure = AskDocumentStructure(
            outline: [],
            pages: [
                AskPageSnapshot(
                    pageIndex: 1,
                    text: "2.4. Let us check the first axiom. For any x and y the product stays inside."
                ),
            ],
            pageCount: 4
        )
        let query = AskStructureLocator.query(in: "what is section 2.4 about")!
        if case .found = AskStructureLocator.locate(query, in: structure) {
            XCTFail("A numbered proof sentence is not a section heading")
        }
    }

    func testLongTitleIsAHeadingAndABibliographyLineIsNot() {
        let titled = AskDocumentStructure(
            outline: [],
            pages: [
                AskPageSnapshot(
                    pageIndex: 2,
                    text: "6. Discriminants of minor-free graphs and completable cycles in the plane\nOrdinary text follows on the next line and is not a heading."
                ),
            ],
            pageCount: 5
        )
        let section6 = AskStructureLocator.query(in: "what is section 6 about")!
        guard case .found(let span) = AskStructureLocator.locate(section6, in: titled) else {
            return XCTFail("Expected the long title")
        }
        XCTAssertEqual(span.startPage, 2)

        let bibliography = AskDocumentStructure(
            outline: [],
            pages: [
                AskPageSnapshot(
                    pageIndex: 0,
                    text: "2. Ada Lovelace, Notes on the analytic engine and its design"
                ),
            ],
            pageCount: 3
        )
        let section2 = AskStructureLocator.query(in: "what is section 2 about")!
        if case .found = AskStructureLocator.locate(section2, in: bibliography) {
            XCTFail("A bibliography line is not a section heading")
        }
    }

    private var paper: AskDocumentStructure {
        AskDocumentStructure(
            outline: [],
            pages: [
                AskPageSnapshot(
                    pageIndex: 0,
                    text: "1. Introduction\nThis note fixes notation for the rest of the argument."
                ),
                AskPageSnapshot(
                    pageIndex: 1,
                    text: "2. Background and notation\nWe recall the notions used below."
                ),
                AskPageSnapshot(
                    pageIndex: 5,
                    text: "2.1. Standing conventions.\nA few definitions used throughout the constructions."
                ),
                AskPageSnapshot(
                    pageIndex: 13,
                    text: "3. Main constructions\nThe constructions occupy the rest of the note."
                ),
                AskPageSnapshot(
                    pageIndex: 14,
                    text: "3.1. From associative envelopes.\nTheorem 3.5. A regular envelope induces a bracket."
                ),
            ],
            pageCount: 25
        )
    }
}
