import XCTest
@testable import Cauchy

final class HighlightModelTests: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func testColourSurvivesARoundTrip() throws {
        let original = Highlight(pageIndex: 3, selectedText: "passage", color: .purple, note: "mine")
        let decoded = try decoder.decode(Highlight.self, from: try encoder.encode(original))

        XCTAssertEqual(decoded.color, .purple)
        XCTAssertEqual(decoded.note, "mine")
    }

    /// Every highlight saved before colours existed has to keep opening, in the
    /// colour it was drawn in at the time.
    func testHighlightSavedBeforeColoursDecodesAsYellow() throws {
        let legacy = """
        {
          "id": "3E7B9F0A-1111-4222-8333-444455556666",
          "pageIndex": 2,
          "selectedText": "old passage",
          "surroundingText": "old passage in context",
          "label": "old passage",
          "messages": [],
          "isPinned": true,
          "createdAt": "2025-01-01T00:00:00Z"
        }
        """
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(Highlight.self, from: Data(legacy.utf8))

        XCTAssertEqual(decoded.color, .yellow)
        XCTAssertNil(decoded.note)
        XCTAssertEqual(decoded.selectedText, "old passage")
    }

    func testLegacyPinsWithoutACategoryStillDecode() throws {
        decoder.dateDecodingStrategy = .iso8601
        let legacy = """
        {
          "id": "3E7B9F0A-1111-4222-8333-444455556666",
          "pageIndex": 0,
          "bounds": {"x": 0.1, "y": 0.1, "width": 0.2, "height": 0.05},
          "label": "Theorem 1.1",
          "createdAt": "2025-01-01T00:00:00Z"
        }
        """

        let pin = try decoder.decode(ReferencePin.self, from: Data(legacy.utf8))
        let highlight = Highlight.fromLegacyPin(pin)

        XCTAssertNil(pin.category)
        XCTAssertEqual(highlight.label, "Theorem 1.1")
        XCTAssertEqual(highlight.color, .yellow)
    }
}

final class LibrarySearchSnippetTests: XCTestCase {
    func testSnippetCentresOnTheMatch() {
        let text = String(repeating: "padding word ", count: 40) + "gradient clipping " + String(repeating: "tail word ", count: 40)

        let snippet = LibrarySearchService.snippet(around: "gradient clipping", in: text)

        XCTAssertTrue(snippet.contains("gradient clipping"))
        XCTAssertTrue(snippet.hasPrefix("…"))
        XCTAssertTrue(snippet.hasSuffix("…"))
        XCTAssertLessThan(snippet.count, text.count)
    }

    func testShortTextIsReturnedWhole() {
        let snippet = LibrarySearchService.snippet(around: "attention", in: "sparse attention here")

        XCTAssertEqual(snippet, "sparse attention here")
    }

    func testWhitespaceIsCollapsed() {
        let snippet = LibrarySearchService.snippet(around: "beta", in: "alpha\n  beta\tgamma")

        XCTAssertEqual(snippet, "alpha beta gamma")
    }
}
