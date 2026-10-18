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

    private var paper: AskDocumentStructure {
        AskDocumentStructure(
            outline: [],
            pages: [
                AskPageSnapshot(
                    pageIndex: 0,
                    text: "1. Introduction\nA Poisson algebra is both an associative algebra and a Lie algebra."
                ),
                AskPageSnapshot(
                    pageIndex: 1,
                    text: "2. Preliminaries and some results\nWe recall the notions used below in this paper."
                ),
                AskPageSnapshot(
                    pageIndex: 5,
                    text: "2.1. Generalities.\nA few definitions used throughout the constructions."
                ),
                AskPageSnapshot(
                    pageIndex: 13,
                    text: "3. Construction theorems\nThe constructions occupy the rest of the paper."
                ),
                AskPageSnapshot(
                    pageIndex: 14,
                    text: "3.1. From BiHom-associative conformal superalgebras.\nTheorem 3.5. If A is regular then the bracket is Poisson."
                ),
            ],
            pageCount: 25
        )
    }
}
