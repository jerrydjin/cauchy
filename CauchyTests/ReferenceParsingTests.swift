import XCTest
@testable import Cauchy

final class ReferenceParsingTests: XCTestCase {
    func testNamedBlockPatternMatchesHeading() {
        let text = "Theorem 1.2 (Main result). Let f be continuous."
        let reference = ReferenceDetector.firstReference(in: text)

        XCTAssertEqual(reference?.kind, .theorem)
        XCTAssertEqual(reference?.number, "1.2")
    }

    func testEquationCitePatternMatchesBareLabel() {
        let text = "as shown by (1.4)"
        let reference = ReferenceDetector.firstReference(in: text)

        XCTAssertEqual(reference?.kind, .equation)
        XCTAssertEqual(reference?.number, "1.4")
    }

    func testEquationCitePatternMatchesPrefixedLabel() {
        let text = "see Eq. (2.3.1) for details"
        let reference = ReferenceDetector.firstReference(in: text)

        XCTAssertEqual(reference?.kind, .equation)
        XCTAssertEqual(reference?.number, "2.3.1")
    }
}
