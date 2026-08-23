import XCTest
@testable import Cauchy

final class HighlightExportServiceTests: XCTestCase {
    private func highlight(
        page: Int,
        text: String,
        title: String? = nil,
        note: String? = nil,
        colour: HighlightColor = .yellow,
        messages: [ThreadMessage] = [],
        createdAt: Date = Date(timeIntervalSince1970: 0)
    ) -> Highlight {
        Highlight(
            pageIndex: page,
            selectedText: text,
            color: colour,
            title: title,
            note: note,
            messages: messages,
            createdAt: createdAt
        )
    }

    func testReadingOrderSortsByPageThenCreation() {
        let late = highlight(page: 1, text: "b", createdAt: Date(timeIntervalSince1970: 200))
        let early = highlight(page: 1, text: "a", createdAt: Date(timeIntervalSince1970: 100))
        let laterPage = highlight(page: 5, text: "c", createdAt: Date(timeIntervalSince1970: 0))

        let ordered = HighlightExportService.readingOrder([laterPage, late, early])

        XCTAssertEqual(ordered.map(\.selectedText), ["a", "b", "c"])
    }

    func testMarkdownIncludesPassageNoteAndConversation() {
        let markdown = HighlightExportService.markdown(
            documentTitle: "Attention Is All You Need",
            highlights: [
                highlight(
                    page: 2,
                    text: "Scaled dot-product attention",
                    title: "Attention scaling",
                    note: "check the 1/sqrt(d) factor",
                    messages: [
                        ThreadMessage(role: .user, content: "Why divide by sqrt(d)?"),
                        ThreadMessage(role: .assistant, content: "To keep the dot products small."),
                    ]
                )
            ]
        )

        XCTAssertTrue(markdown.hasPrefix("# Attention Is All You Need"))
        XCTAssertTrue(markdown.contains("## Attention scaling"))
        XCTAssertTrue(markdown.contains("**Page 3**"))
        XCTAssertTrue(markdown.contains("> Scaled dot-product attention"))
        XCTAssertTrue(markdown.contains("**Note:** check the 1/sqrt(d) factor"))
        XCTAssertTrue(markdown.contains("**Q:** Why divide by sqrt(d)?"))
        XCTAssertTrue(markdown.contains("To keep the dot products small."))
    }

    /// A passage spanning several lines has to stay inside one block quote —
    /// an unprefixed line silently ends the quote in every Markdown renderer.
    func testMultiLinePassageQuotesEveryLine() {
        let markdown = HighlightExportService.markdown(
            documentTitle: "Doc",
            highlights: [highlight(page: 0, text: "first line\nsecond line")]
        )

        XCTAssertTrue(markdown.contains("> first line\n> second line"))
    }

    func testMarkdownNamesANonDefaultColour() {
        let plain = HighlightExportService.markdown(
            documentTitle: "Doc",
            highlights: [highlight(page: 0, text: "x", colour: .yellow)]
        )
        let tinted = HighlightExportService.markdown(
            documentTitle: "Doc",
            highlights: [highlight(page: 0, text: "x", colour: .blue)]
        )

        XCTAssertFalse(plain.contains("Yellow"))
        XCTAssertTrue(tinted.contains("Blue"))
    }

    func testSingleThreadMarkdownStandsAlone() {
        let markdown = HighlightExportService.markdown(
            for: highlight(page: 0, text: "one passage", title: "Just this"),
            documentTitle: "Doc"
        )

        XCTAssertTrue(markdown.contains("# Doc"))
        XCTAssertTrue(markdown.contains("## Just this"))
        XCTAssertFalse(markdown.contains("---"))
    }
}
