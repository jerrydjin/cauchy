import XCTest
@testable import Cauchy

@MainActor
final class AskStructureLocatorTests: XCTestCase {
    private let rect = NormalizedRect(x: 0, y: 0, width: 0.2, height: 0.04)

    private var textbook: AskDocumentStructure {
        AskDocumentStructure(
            outline: [
                AskOutlineNode(title: "Chapter 1. Sets", pageIndex: 0, children: []),
                AskOutlineNode(title: "Chapter 2. Groups", pageIndex: 10, children: [
                    AskOutlineNode(title: "2.1 Groups", pageIndex: 10, children: []),
                    AskOutlineNode(title: "2.2 Actions", pageIndex: 14, children: []),
                ]),
                AskOutlineNode(title: "Chapter 3. Rings", pageIndex: 20, children: []),
                AskOutlineNode(title: "Part II", pageIndex: 40, children: [
                    AskOutlineNode(title: "3.4 Fields", pageIndex: 44, children: []),
                ]),
                AskOutlineNode(title: "Part III", pageIndex: 60, children: []),
            ],
            pages: [
                AskPageSnapshot(
                    pageIndex: 10,
                    text: "Chapter 2\nThis chapter studies groups and their actions in detail."
                ),
                AskPageSnapshot(
                    pageIndex: 14,
                    text: "2.2 Actions\nA group acts on a set when each element gives a permutation."
                ),
                AskPageSnapshot(
                    pageIndex: 36,
                    text: "Unrelated later material about integrals on pages far from chapter 2."
                ),
            ],
            pageCount: 80
        )
    }

    func testChapterQueryUsesTheOutlineInsteadOfLaterPages() {
        let query = AskStructureLocator.query(in: "what is chapter 2 about")
        XCTAssertEqual(query?.displayName, "Chapter 2")

        guard case .found(let span) = AskStructureLocator.locate(query!, in: textbook) else {
            return XCTFail("Expected chapter 2")
        }
        XCTAssertEqual(span.startPage, 10)
        XCTAssertEqual(span.endPage, 20)
        XCTAssertEqual(span.label, "Chapter 2. Groups")
        XCTAssertEqual(span.headings.map(\.label), ["§2.1 Groups", "§2.2 Actions"])

        let retrieval = AskContextRetriever.retrieve(
            question: "what is chapter 2 about",
            selectedText: "",
            surroundingText: "",
            pageIndex: nil,
            referenceIndex: nil,
            documentIndex: UnrelatedPassages(),
            passageLimit: 3,
            structuralQuery: query,
            structure: textbook,
            passageCharacterBudget: 800
        )
        XCTAssertNil(retrieval.structureMissMessage)
        XCTAssertTrue(retrieval.passages.contains { $0.contains("studies groups") })
        XCTAssertTrue(retrieval.passages.contains { $0.contains("[p. 11]") })
        XCTAssertFalse(retrieval.passages.contains { $0.contains("integrals") })
        XCTAssertFalse(retrieval.passages.contains { $0.contains("[p. 36]") })
        XCTAssertEqual(retrieval.passageRecords.first?.label, "Chapter 2. Groups")
    }

    func testSectionAndPartQueriesMatchTheOutline() {
        let section = AskStructureLocator.query(in: "explain section 3.4")
        guard case .found(let sectionSpan) = AskStructureLocator.locate(section!, in: textbook) else {
            return XCTFail("Expected section 3.4")
        }
        XCTAssertEqual(sectionSpan.startPage, 44)
        XCTAssertEqual(sectionSpan.endPage, 60)
        XCTAssertEqual(sectionSpan.label, "§3.4 Fields")

        let part = AskStructureLocator.query(in: "what's in part II")
        guard case .found(let partSpan) = AskStructureLocator.locate(part!, in: textbook) else {
            return XCTFail("Expected part II")
        }
        XCTAssertEqual(partSpan.startPage, 40)
        XCTAssertEqual(partSpan.endPage, 60)
        XCTAssertEqual(partSpan.label, "Part II")
    }

    func testChapterRomanNumeralMatchesAnArabicQuestion() {
        let structure = AskDocumentStructure(
            outline: [
                AskOutlineNode(title: "Chapter II. Groups", pageIndex: 8, children: []),
                AskOutlineNode(title: "Chapter III", pageIndex: 16, children: []),
            ],
            pages: [],
            pageCount: 30
        )
        let query = AskStructureLocator.query(in: "What is chapter 2 about?")
        guard case .found(let span) = AskStructureLocator.locate(query!, in: structure) else {
            return XCTFail("Expected chapter II")
        }
        XCTAssertEqual(span.startPage, 8)
        XCTAssertEqual(span.endPage, 16)
    }

    func testDetectedHeadingIsUsedWhenTheOutlineIsMissing() {
        let structure = AskDocumentStructure(
            outline: [],
            pages: [
                AskPageSnapshot(pageIndex: 4, text: "Preface\nHow to read these notes."),
                AskPageSnapshot(
                    pageIndex: 9,
                    text: "Chapter 2\nGroups begin here with a definition that is long enough to quote."
                ),
                AskPageSnapshot(pageIndex: 18, text: "Chapter 3\nRings begin after the group theory."),
            ],
            pageCount: 30
        )
        let query = AskStructureLocator.query(in: "what is ch. 2 about")
        guard case .found(let span) = AskStructureLocator.locate(query!, in: structure) else {
            return XCTFail("Expected a detected chapter heading")
        }
        XCTAssertEqual(span.startPage, 9)
        XCTAssertEqual(span.endPage, 18)
        let passages = AskStructureLocator.passages(for: span, in: structure, characterBudget: 800, limit: 3)
        XCTAssertTrue(passages.contains { $0.text.contains("Groups begin here") })
    }

    func testContentsPageSuppliesTheSpanWhenNothingElseDoes() {
        let structure = AskDocumentStructure(
            outline: [],
            pages: [
                AskPageSnapshot(
                    pageIndex: 1,
                    text: """
                    Contents

                    Chapter 1. Sets .... 1
                    Chapter 2. Groups .... 15
                    Chapter 3. Rings .... 40
                    Appendix .... 70
                    Index .... 80
                    """
                ),
            ],
            pageCount: 90
        )
        let query = AskStructureLocator.query(in: "what is chapter 2 about")
        guard case .found(let span) = AskStructureLocator.locate(query!, in: structure) else {
            return XCTFail("Expected a contents entry")
        }
        XCTAssertEqual(span.startPage, 14)
        XCTAssertEqual(span.endPage, 39)
    }

    func testContentsSpanRunsThroughTheChapterRatherThanItsFirstSection() {
        let structure = AskDocumentStructure(
            outline: [],
            pages: [
                AskPageSnapshot(
                    pageIndex: 1,
                    text: """
                    Contents

                    Chapter 1. Sets .... 1
                    Chapter 2. Groups .... 15
                    2.1 Groups .... 15
                    2.2 Actions .... 22
                    Chapter 3. Rings .... 40
                    """
                ),
            ],
            pageCount: 90
        )
        let query = AskStructureLocator.query(in: "what is chapter 2 about")
        guard case .found(let span) = AskStructureLocator.locate(query!, in: structure) else {
            return XCTFail("Expected a contents entry")
        }
        XCTAssertEqual(span.startPage, 14)
        XCTAssertEqual(span.endPage, 39)
    }

    func testANumberedSentenceDoesNotReplaceTheChapterHeading() {
        let structure = AskDocumentStructure(
            outline: [],
            pages: [
                AskPageSnapshot(pageIndex: 2, text: "2 Integrals appear here."),
                AskPageSnapshot(
                    pageIndex: 12,
                    text: "Chapter 2\nGroups begin with a definition long enough to keep."
                ),
                AskPageSnapshot(pageIndex: 20, text: "Chapter 3\nRings follow the groups."),
            ],
            pageCount: 30
        )
        let query = AskStructureLocator.query(in: "what is chapter 2 about")
        guard case .found(let span) = AskStructureLocator.locate(query!, in: structure) else {
            return XCTFail("Expected the chapter heading")
        }
        XCTAssertEqual(span.startPage, 12)
        XCTAssertEqual(span.endPage, 20)
    }

    func testAMissingChapterSaysWhatWasSearchedAndDoesNotAskForAPage() {
        let query = AskStructureLocator.query(in: "what is chapter 9 about")!
        guard case .missing(let message) = AskStructureLocator.locate(query, in: textbook) else {
            return XCTFail("Expected a miss")
        }
        XCTAssertTrue(message.contains("Chapter 9"))
        XCTAssertTrue(message.contains("outline, headings, or contents"))
        XCTAssertTrue(message.contains("Highlight a passage or rephrase"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("share"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("upload"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("paste"))

        let retrieval = AskContextRetriever.retrieve(
            question: "what is chapter 9 about",
            selectedText: "",
            surroundingText: "",
            pageIndex: nil,
            referenceIndex: nil,
            documentIndex: UnrelatedPassages(),
            passageLimit: 5,
            structuralQuery: query,
            structure: textbook
        )
        XCTAssertEqual(retrieval.structureMissMessage, message)
        XCTAssertTrue(retrieval.passages.isEmpty)
        XCTAssertTrue(retrieval.statements.isEmpty)
    }

    func testSourceMarkersBecomePageChipsAndUnknownMarkersAreDropped() {
        let anchors = [
            AnswerSourceAnchor(label: "Chapter 2. Groups", pageIndex: 35, region: rect, sourceID: "P1"),
            AnswerSourceAnchor(label: "§2.1 Groups", pageIndex: 38, region: rect, sourceID: "P2"),
        ]
        let runs = AnswerSourceMarkers.runs(in: "Groups are the topic. [P1][P2][P9]", anchors: anchors)
        let chips = runs.compactMap { run -> AnswerSourceMarkers.Chip? in
            if case .chip(let chip) = run { return chip }
            return nil
        }
        XCTAssertEqual(chips.map(\.pageLabel), ["p. 36", "p. 39"])
        XCTAssertEqual(chips.map(\.pageIndex), [35, 38])
        XCTAssertTrue(runs.allSatisfy { run in
            if case .text(let text) = run { return !text.contains("[P") }
            return true
        })
        XCTAssertEqual(
            AnswerSourceMarkers.strippingMarkers(from: "Groups are the topic. [P1][P2][P5]"),
            "Groups are the topic."
        )
    }

    func testOpeningExcerptStaysInsideThePassageBudget() {
        let long = String(repeating: "group ", count: 400)
        let structure = AskDocumentStructure(
            outline: [],
            pages: [AskPageSnapshot(pageIndex: 3, text: "Chapter 2\n\(long)")],
            pageCount: 5
        )
        let query = AskStructureLocator.query(in: "chapter 2")!
        guard case .found(let span) = AskStructureLocator.locate(query, in: structure) else {
            return XCTFail("Expected the heading")
        }
        let passages = AskStructureLocator.passages(for: span, in: structure, characterBudget: 800, limit: 3)
        let total = passages.reduce(0) { $0 + $1.text.count }
        XCTAssertLessThanOrEqual(total, 800)
        XCTAssertFalse(passages.isEmpty)
    }
}

private struct UnrelatedPassages: DocumentIndexProtocol {
    func passages(matching query: String, limit: Int, excludingPage: Int?) -> [String] {
        ["[p. 36] unrelated chapter about integrals", "[p. 59] another unrelated passage"]
    }
}
