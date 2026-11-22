import XCTest
@testable import Cauchy

final class InlineFlowLayoutTests: XCTestCase {
    func testSegmentAfterMathWrapsWhenItExceedsRemainingWidth() {
        let result = InlineFlowLayoutEngine.layout(
            tokens: [
                InlineFlowToken(size: CGSize(width: 40, height: 20)),
                InlineFlowToken(size: CGSize(width: 180, height: 20)),
            ],
            maxWidth: 200,
            horizontalSpacing: 3,
            verticalSpacing: 4
        )

        XCTAssertEqual(result.placements.count, 2)
        XCTAssertEqual(result.placements[0].x, 0)
        XCTAssertEqual(result.placements[1].x, 0)
        XCTAssertEqual(result.placements[1].y, 24)
        XCTAssertLessThanOrEqual(result.placements[0].x + result.placements[0].size.width, 200)
        XCTAssertLessThanOrEqual(result.placements[1].x + result.placements[1].size.width, 200)
    }

    func testWordMovesToNextRowAtLeftMargin() {
        let result = InlineFlowLayoutEngine.layout(
            tokens: [
                InlineFlowToken(size: CGSize(width: 120, height: 20)),
                InlineFlowToken(size: CGSize(width: 70, height: 20)),
                InlineFlowToken(size: CGSize(width: 50, height: 20)),
            ],
            maxWidth: 200,
            horizontalSpacing: 3,
            verticalSpacing: 4
        )

        XCTAssertEqual(result.placements.count, 3)
        XCTAssertEqual(result.placements[0].x, 0)
        XCTAssertEqual(result.placements[1].x, 123)
        XCTAssertEqual(result.placements[2].x, 0)
        XCTAssertEqual(result.placements[2].y, 24)
    }

    func testRemainingWidthUsesSpaceAfterLeadingSegments() {
        let result = InlineFlowLayoutEngine.layout(
            tokens: [
                InlineFlowToken(size: CGSize(width: 60, height: 20)),
                InlineFlowToken(size: CGSize(width: 130, height: 20)),
            ],
            maxWidth: 200,
            horizontalSpacing: 3,
            verticalSpacing: 4
        )

        XCTAssertEqual(result.placements.count, 2)
        XCTAssertEqual(result.placements[0].x, 0)
        XCTAssertEqual(result.placements[1].x, 63)
        XCTAssertEqual(result.placements[1].y, 0)
        XCTAssertEqual(result.placements[0].x + result.placements[0].size.width + 3 + result.placements[1].size.width, 193)
    }

    func testLayoutWidthNeverExceedsMaxWidth() {
        let result = InlineFlowLayoutEngine.layout(
            tokens: [
                InlineFlowToken(size: CGSize(width: 90, height: 20)),
                InlineFlowToken(size: CGSize(width: 90, height: 20)),
                InlineFlowToken(size: CGSize(width: 90, height: 20)),
            ],
            maxWidth: 200,
            horizontalSpacing: 3,
            verticalSpacing: 4
        )

        XCTAssertLessThanOrEqual(result.size.width, 200)
        for placement in result.placements {
            XCTAssertLessThanOrEqual(placement.x + placement.size.width, 200)
        }
    }

    func testEquationOnItsOwnLineIsCentred() {
        let result = InlineFlowLayoutEngine.layout(
            tokens: [
                InlineFlowToken(size: CGSize(width: 160, height: 20)),
                InlineFlowToken(size: CGSize(width: 120, height: 24), centersWhenAlone: true),
            ],
            maxWidth: 200,
            horizontalSpacing: 3,
            verticalSpacing: 4
        )

        XCTAssertEqual(result.placements[1].y, 24)
        XCTAssertEqual(result.placements[1].x, 40)
        XCTAssertEqual(result.size.width, 200)
    }

    /// A display that fits the card keeps its own width and is centred.
    /// One that is wider is scaled to the text column and stays inside it.
    func testNarrowDisplayIsCentredAndWideDisplayScalesToTheCard() {
        let column = CardMathLayout.textWidth
        let narrowNatural: CGFloat = 120
        let narrow = CardMathLayout.reportedWidth(naturalWidth: narrowNatural, columnWidth: column)
        XCTAssertEqual(narrow, narrowNatural)
        XCTAssertFalse(CardMathLayout.scalesToColumn(naturalWidth: narrowNatural, columnWidth: column))

        let centred = InlineFlowLayoutEngine.layout(
            tokens: [
                InlineFlowToken(size: CGSize(width: narrow, height: 36), centersWhenAlone: true),
            ],
            maxWidth: column,
            horizontalSpacing: 0,
            verticalSpacing: 0
        )
        XCTAssertEqual(centred.placements[0].x, (column - narrow) / 2, accuracy: 0.5)
        XCTAssertLessThanOrEqual(centred.placements[0].x + centred.placements[0].size.width, column)

        let wideNatural = column + 180
        let wide = CardMathLayout.reportedWidth(naturalWidth: wideNatural, columnWidth: column)
        XCTAssertEqual(wide, column)
        XCTAssertLessThan(wide, wideNatural)
        XCTAssertTrue(CardMathLayout.scalesToColumn(naturalWidth: wideNatural, columnWidth: column))

        let scaled = InlineFlowLayoutEngine.layout(
            tokens: [
                InlineFlowToken(size: CGSize(width: wide, height: 36), centersWhenAlone: true),
            ],
            maxWidth: column,
            horizontalSpacing: 0,
            verticalSpacing: 0
        )
        XCTAssertEqual(scaled.placements[0].size.width, column)
        XCTAssertEqual(scaled.placements[0].x, 0)
        XCTAssertLessThanOrEqual(scaled.placements[0].x + scaled.placements[0].size.width, column)
    }

    func testInlineEquationStaysBesideTheWords() {
        let result = InlineFlowLayoutEngine.layout(
            tokens: [
                InlineFlowToken(size: CGSize(width: 40, height: 20)),
                InlineFlowToken(size: CGSize(width: 80, height: 20), centersWhenAlone: true),
            ],
            maxWidth: 200,
            horizontalSpacing: 3,
            verticalSpacing: 4
        )

        XCTAssertEqual(result.placements[1].x, 43)
        XCTAssertEqual(result.placements[1].y, 0)
    }
}
