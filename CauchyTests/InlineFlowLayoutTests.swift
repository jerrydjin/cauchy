import XCTest
@testable import Cauchy

final class InlineFlowLayoutTests: XCTestCase {
    func testSegmentAfterMathWrapsWhenItExceedsRemainingWidth() {
        let result = InlineFlowLayoutEngine.layout(
            segmentSizes: [
                CGSize(width: 40, height: 20),
                CGSize(width: 180, height: 20),
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
            segmentSizes: [
                CGSize(width: 120, height: 20),
                CGSize(width: 70, height: 20),
                CGSize(width: 50, height: 20),
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
            segmentSizes: [
                CGSize(width: 60, height: 20),
                CGSize(width: 130, height: 20),
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
            segmentSizes: [
                CGSize(width: 90, height: 20),
                CGSize(width: 90, height: 20),
                CGSize(width: 90, height: 20),
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
}
