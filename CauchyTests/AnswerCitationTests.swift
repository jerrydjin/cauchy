import XCTest
@testable import Cauchy

final class AnswerCitationTests: XCTestCase {
    func testPageTagSitsAtTheEndOfTheClaimItSupports() {
        let lines = AnswerCitationLayout.claimLines(
            in: "By Proposition 5.3.1 [R1], $f$ is continuous exactly when the preimage is open.",
            anchors: [anchor("R1", page: 38, label: "Proposition 5.3.1")]
        )

        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(
            lines[0].text,
            "By Proposition 5.3.1, $f$ is continuous exactly when the preimage is open."
        )
        XCTAssertFalse(lines[0].text.contains("["))
        XCTAssertEqual(lines[0].chips.map(\.pageLabel), ["p. 39"])
        XCTAssertEqual(lines[0].chips.map(\.sourceID), ["R1"])
    }

    func testEachClaimKeepsItsOwnTag() {
        let text = """
        A set is closed exactly when its complement is open. [R2] By Proposition 5.3.1, f is continuous. [R1]
        """
        let lines = AnswerCitationLayout.claimLines(
            in: text,
            anchors: [
                anchor("R1", page: 38, label: "Proposition 5.3.1"),
                anchor("R2", page: 36, label: "Open and closed sets"),
            ]
        )

        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].text, "A set is closed exactly when its complement is open.")
        XCTAssertEqual(lines[0].chips.map(\.pageLabel), ["p. 37"])
        XCTAssertEqual(lines[1].text, "By Proposition 5.3.1, f is continuous.")
        XCTAssertEqual(lines[1].chips.map(\.pageLabel), ["p. 39"])
    }

    func testSourcesListIsCitedPagesOnlyAndDeduped() {
        let anchors = [
            anchor("R1", page: 38, label: "Proposition 5.3.1"),
            anchor("R1", page: 38, label: "Proposition 5.3.1 again"),
            anchor("S1", page: 38, label: "Selected passage"),
            anchor("R2", page: 36, label: "Open and closed sets"),
            anchor("P3", page: 65, label: "Compactness implies sequential compactness"),
            anchor("P4", page: 6, label: "Continuous partial derivatives"),
        ]
        let content = """
        A set is closed exactly when its complement is open. [R2]
        By Proposition 5.3.1, f is continuous. [R1] [R1]
        The selected sentence agrees. [S1]
        Nothing here cites compactness. [P9]
        """

        let pages = CitedSourceSummary.pages(in: content, anchors: anchors)

        XCTAssertEqual(pages.map(\.pageIndex), [36, 38])
        XCTAssertEqual(pages.map(\.pageLabel), ["p. 37", "p. 39"])
        XCTAssertEqual(pages.map { $0.anchor.sourceID }, ["R2", "R1"])
        XCTAssertFalse(pages.contains { $0.anchor.label.contains("Compactness") })
        XCTAssertFalse(pages.contains { $0.anchor.label.contains("derivatives") })
        XCTAssertEqual(CitedSourceSummary.disclosureLabel(pageCount: pages.count), "Sources · 2 pages")
        XCTAssertEqual(CitedSourceSummary.disclosureLabel(pageCount: 1), "Sources · 1 page")
    }

    func testPageTagUsesTheShortFormAndASpanUsesPages() {
        XCTAssertEqual(CitationPageLabel.short(firstPageIndex: 38, lastPageIndex: 38), "p. 39")
        XCTAssertEqual(CitationPageLabel.short(firstPageIndex: 36, lastPageIndex: 38), "pp. 37–39")
        XCTAssertEqual(CitationPageLabel.voiceOver(firstPageIndex: 38, lastPageIndex: 38), "Open page 39")
        XCTAssertEqual(CitationPageLabel.voiceOver(firstPageIndex: 36, lastPageIndex: 38), "Open pages 37 to 39")
    }

    func testSourcesHideWhenNothingIsCited() {
        let anchors = [anchor("P3", page: 65, label: "Compactness")]
        let pages = CitedSourceSummary.pages(
            in: "The notes do not settle this.",
            anchors: anchors
        )

        XCTAssertTrue(pages.isEmpty)
    }

    func testUnlocatablePassageFallsBackToThePageWithoutAHighlight() {
        let missing = anchor("R1", page: 4, label: "Missing", region: NormalizedRect(x: 0, y: 0, width: 0, height: 0))
        XCTAssertEqual(
            AnswerSourceNavigation.resolve(missing, pageCount: 10),
            .pageOnly(pageIndex: 4)
        )

        let offPage = anchor("R1", page: 4, label: "Off", region: NormalizedRect(x: 2, y: 0, width: 0.2, height: 0.1))
        XCTAssertEqual(
            AnswerSourceNavigation.resolve(offPage, pageCount: 10),
            .pageOnly(pageIndex: 4)
        )

        let notANumber = anchor(
            "R1",
            page: 1,
            label: "Nan",
            region: NormalizedRect(x: .nan, y: 0, width: 0.2, height: 0.1)
        )
        XCTAssertEqual(
            AnswerSourceNavigation.resolve(notANumber, pageCount: 10),
            .pageOnly(pageIndex: 1)
        )

        XCTAssertNil(AnswerSourceNavigation.resolve(missing, pageCount: 4))

        let exact = NormalizedRect(x: 0.1, y: 0.42, width: 0.7, height: 0.04)
        let located = anchor("R1", page: 38, label: "Proposition 5.3.1", region: exact)
        XCTAssertEqual(
            AnswerSourceNavigation.resolve(located, pageCount: 80),
            .highlighted(pageIndex: 38, region: exact)
        )
    }

    func testHighlightStaysUntilThePassageScrollsAway() {
        let region = NormalizedRect(x: 0.1, y: 0.4, width: 0.8, height: 0.05)
        var session = CitationHighlightSession()
        session.show(CitationPassageHighlight(pageIndex: 3, region: region))

        session.userMoved(to: viewport(page: 0, visible: NormalizedRect(x: 0, y: 0, width: 1, height: 0.2)))
        XCTAssertNotNil(session.highlight)
        XCTAssertFalse(session.armed)

        session.userMoved(to: viewport(page: 3, visible: NormalizedRect(x: 0, y: 0.3, width: 1, height: 0.3)))
        XCTAssertEqual(session.highlight?.region, region)
        XCTAssertTrue(session.armed)

        session.userMoved(to: viewport(page: 3, visible: NormalizedRect(x: 0, y: 0.35, width: 1, height: 0.3)))
        XCTAssertNotNil(session.highlight)

        session.userMoved(to: viewport(page: 3, visible: NormalizedRect(x: 0, y: 0.8, width: 1, height: 0.2)))
        XCTAssertNil(session.highlight)
        XCTAssertFalse(session.armed)
    }

    func testInlineLinkStaysInTheSentenceAndKeepsTheComma() {
        let text = "By Proposition 5.3.1, f is continuous exactly when the preimage is open."
        let match = DetectedReferenceMatch(
            reference: DetectedReference(kind: .proposition, number: "5.3.1"),
            range: text.range(of: "Proposition 5.3.1")!
        )
        let pieces = InlineReferenceFlow.pieces(in: text, matches: [match])
        let labels = pieces.map { piece -> String in
            switch piece {
            case .text(let value): return "t:\(value)"
            case .link(let label, let suffix, _): return "l:\(label)|\(suffix)"
            }
        }

        XCTAssertEqual(labels, [
            "t:By ",
            "l:Proposition |",
            "l:5.3.1|, ",
            "t:f ",
            "t:is ",
            "t:continuous ",
            "t:exactly ",
            "t:when ",
            "t:the ",
            "t:preimage ",
            "t:is ",
            "t:open.",
        ])
        XCTAssertFalse(pieces.contains { piece in
            if case .text(let value) = piece {
                return value.trimmingCharacters(in: .whitespaces) == ","
            }
            return false
        })

        let widths: [CGFloat] = pieces.map { piece in
            let label: String
            switch piece {
            case .text(let value): label = value
            case .link(let value, let suffix, _): label = value + suffix
            }
            return CGFloat(label.count) * 7
        }
        let result = InlineFlowLayoutEngine.layout(
            tokens: widths.map { InlineFlowToken(size: CGSize(width: $0, height: 18)) },
            maxWidth: 120,
            horizontalSpacing: 0,
            verticalSpacing: 2
        )

        XCTAssertEqual(result.placements[0].y, result.placements[1].y, "By and Proposition share a line")
        XCTAssertGreaterThan(result.placements[2].y, result.placements[1].y)
        if case .link(let label, let suffix, _) = pieces[2] {
            XCTAssertEqual(label, "5.3.1")
            XCTAssertEqual(suffix, ", ", "the comma rides on the number but is not part of the link")
        } else {
            XCTFail("The wrapped token should still be the link, comma included")
        }

        let rows = Dictionary(grouping: pieces.indices, by: { result.placements[$0].y })
        for indices in rows.values {
            let row = indices.map { pieces[$0] }
            let text = row.map { piece -> String in
                switch piece {
                case .text(let value): return value
                case .link(let label, let suffix, _): return label + suffix
                }
            }.joined()
            XCTAssertNotEqual(text.trimmingCharacters(in: .whitespaces), ",")
            XCTAssertFalse(text.trimmingCharacters(in: .whitespaces) == "Proposition 5.3.1")
        }
    }

    func testOnlyIndexedResultsBecomeLinks() {
        let text = "By Proposition 5.3.1, and not by Theorem 9.9."
        let known: Set<ReferenceKey> = [ReferenceKey(kind: .proposition, number: "5.3.1")]
        let linked = AssistantResponseValidator.linkableReferences(in: text, known: known)

        XCTAssertEqual(linked.map(\.reference.displayName), ["Proposition 5.3.1"])
        XCTAssertTrue(AssistantResponseValidator.linkableReferences(in: text, known: []).isEmpty)
    }

    private func anchor(
        _ id: String,
        page: Int,
        label: String,
        region: NormalizedRect = NormalizedRect(x: 0.1, y: 0.4, width: 0.7, height: 0.04)
    ) -> AnswerSourceAnchor {
        AnswerSourceAnchor(label: label, pageIndex: page, region: region, sourceID: id)
    }

    private func viewport(page: Int, visible: NormalizedRect?) -> ViewportState {
        ViewportState(
            pageIndex: page,
            scaleFactor: 1,
            visibleRectNormalized: visible,
            linkedReferenceLinkID: nil,
            syncMode: .independent
        )
    }
}
