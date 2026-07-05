import XCTest
@testable import Cauchy

final class AssistantResponseValidatorTests: XCTestCase {
    func testAcceptsProperlyDelimitedReply() {
        let text = """
        Since $f$ is continuous, for any $\\epsilon > 0$ there exists $\\delta > 0$ such that
        $$|f(x) - f(a)| \\leq \\frac{\\epsilon}{2}$$
        """
        XCTAssertTrue(AssistantResponseValidator.isDisplayReady(text))
    }

    func testRejectsBareFractionOutsideDelimiters() {
        let text = "We have |f(x) - f(a)| \\leq \\frac{\\epsilon}{2} as needed."
        XCTAssertTrue(AssistantResponseValidator.hasUndelimitedLaTeX(text))
        XCTAssertFalse(AssistantResponseValidator.isDisplayReady(text))
    }

    func testNormalizerConvertsParenDelimiters() {
        let raw = "Note that \\(x \\in X\\) and \\[\\frac{a}{b}\\]"
        let normalized = AssistantResponseNormalizer.normalize(raw)
        XCTAssertTrue(normalized.contains("$x \\in X$"))
        XCTAssertTrue(normalized.contains("$$\\frac{a}{b}$$"))
    }

    func testNormalizerWrapsBareTriangleInequalityLine() {
        let raw = """
        \\left| (f+g)(x) - (f+g)(a) \\right| = \\left| (f(x) - f(a)) + (g(x) - g(a)) \\right|\\leq \\left| f(x) - f(a) \\right| + \\left| g(x) - g(a) \\right|< \\frac{\\epsilon}{2} + \\frac{\\epsilon}{2} = \\epsilon
        """
        let normalized = AssistantResponseNormalizer.normalize(raw)
        XCTAssertTrue(normalized.contains("$$"))
        XCTAssertTrue(normalized.contains("\\left|"))
        XCTAssertFalse(AssistantResponseValidator.hasUndelimitedLaTeX(normalized))
        XCTAssertTrue(AssistantResponseValidator.isDisplayReady(normalized))
    }

    func testParserRendersWrappedTriangleInequality() {
        let raw = """
        \\left| (f+g)(x) - (f+g)(a) \\right| = \\left| (f(x) - f(a)) + (g(x) - g(a)) \\right|\\leq \\left| f(x) - f(a) \\right| + \\left| g(x) - g(a) \\right|< \\frac{\\epsilon}{2} + \\frac{\\epsilon}{2} = \\epsilon
        """
        let segments = MessageContentParser.parse(raw)
        XCTAssertTrue(segments.contains { segment in
            if case .displayMath(let latex) = segment {
                return latex.contains("\\left|") && latex.contains("\\frac{\\epsilon}{2}")
            }
            return false
        })
    }

    func testBlocksKeepSentenceTogetherAcrossSoftLineBreak() {
        let content = "Case 1: If $\\lambda = 0$, then $0 \\cdot f$\nis the constant zero function."
        let segments = MessageContentParser.parse(content)
        let blocks = MessageContentParser.blocks(from: segments)

        XCTAssertEqual(blocks.count, 1)
        guard case .inlineLine(let line) = blocks[0] else {
            return XCTFail("Expected a single inline line block")
        }

        let text = line.compactMap { segment -> String? in
            if case .text(let value) = segment { return value }
            return nil
        }.joined()

        XCTAssertTrue(text.contains("then"))
        XCTAssertTrue(text.contains("is the constant zero function"))
    }

    func testLemmaStyleInlineLineProducesFlowTokens() {
        let content = "Let $X$ be a metric space, and let $Y \\subseteq X$ be a subset, considering the metric induced from $X$."
        let segments = MessageContentParser.parse(content)
        let blocks = MessageContentParser.blocks(from: segments)

        XCTAssertEqual(blocks.count, 1)
        guard case .inlineLine(let line) = blocks[0] else {
            return XCTFail("Expected a single inline line block")
        }

        let flowTokens = MessageContentParser.flowTokens(from: line)
        XCTAssertGreaterThan(flowTokens.count, 5)

        let mathCount = flowTokens.filter {
            if case .inlineMath = $0 { return true }
            return false
        }.count
        XCTAssertEqual(mathCount, 3)

        let text = flowTokens.compactMap { segment -> String? in
            if case .text(let value) = segment { return value }
            return nil
        }.joined()

        XCTAssertTrue(text.contains("Let"))
        XCTAssertTrue(text.contains("metric induced from"))
    }
}
