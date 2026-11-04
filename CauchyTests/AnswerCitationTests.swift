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
        XCTAssertEqual(lines[0].chips.map(\.pageLabel), ["39"])
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
        XCTAssertEqual(lines[0].chips.map(\.pageLabel), ["37"])
        XCTAssertEqual(lines[1].text, "By Proposition 5.3.1, f is continuous.")
        XCTAssertEqual(lines[1].chips.map(\.pageLabel), ["39"])
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
        XCTAssertEqual(pages.map(\.pageLabel), ["37", "39"])
        XCTAssertEqual(pages.map { $0.anchor.sourceID }, ["R2", "R1"])
        XCTAssertFalse(pages.contains { $0.anchor.label.contains("Compactness") })
        XCTAssertFalse(pages.contains { $0.anchor.label.contains("derivatives") })
        XCTAssertEqual(CitedSourceSummary.disclosureLabel(pageCount: pages.count), "Sources · 2 pages")
        XCTAssertEqual(CitedSourceSummary.disclosureLabel(pageCount: 1), "Sources · 1 page")
    }

    func testPageMarkIsTheNumberAndASpanIsARange() {
        XCTAssertEqual(CitationPageLabel.short(firstPageIndex: 38, lastPageIndex: 38), "39")
        XCTAssertEqual(CitationPageLabel.short(firstPageIndex: 36, lastPageIndex: 38), "37–39")
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

    func testLinkTintIsTheSharedOpaqueLightBlue() {
        XCTAssertEqual(CitationChrome.linkRed, 138.0 / 255.0, accuracy: 1e-12)
        XCTAssertEqual(CitationChrome.linkGreen, 180.0 / 255.0, accuracy: 1e-12)
        XCTAssertEqual(CitationChrome.linkBlue, 248.0 / 255.0, accuracy: 1e-12)
        let rendered = (
            Int((CitationChrome.linkRed * 255).rounded()),
            Int((CitationChrome.linkGreen * 255).rounded()),
            Int((CitationChrome.linkBlue * 255).rounded())
        )
        XCTAssertEqual(rendered.0, 138)
        XCTAssertEqual(rendered.1, 180)
        XCTAssertEqual(rendered.2, 248)
    }

    func testPinnedPassageLineCollapsesWhitespace() {
        let passage = PinnedPassage(
            pageIndex: 38,
            excerpt: "By taking\ncomplements,  one can show the following.",
            fingerprint: "complements",
            bounds: nil
        )
        XCTAssertEqual(passage.line, "p. 39 · By taking complements, one can show the following.")
    }

    func testChipStaysUntilDismissedOrReplacedAndIgnoresTheSameSelection() {
        var chip = PinnedPassageChip()
        let selected = samplePassage("By taking complements, one can show the following.", page: 38, fingerprint: "a")
        XCTAssertTrue(chip.noteSelection(selected))
        XCTAssertEqual(chip.messagePassage?.pageIndex, 38)
        XCTAssertEqual(chip.messagePassage?.excerpt, selected.excerpt)

        // Sending a follow-up does not touch the chip. Only dismiss or a new
        // selection does.
        XCTAssertEqual(chip.passage, selected)

        chip.dismiss()
        XCTAssertNil(chip.passage)
        XCTAssertNil(chip.messagePassage)
        XCTAssertFalse(chip.noteSelection(selected))
        XCTAssertNil(chip.passage)

        XCTAssertTrue(chip.noteSelection(selected, explicit: true))
        XCTAssertEqual(chip.passage, selected)

        chip.dismiss()
        let replacement = samplePassage("A different sentence.", page: 10, fingerprint: "b")
        XCTAssertTrue(chip.noteSelection(replacement))
        XCTAssertEqual(chip.passage?.line, "p. 11 · A different sentence.")
    }

    /// Synthetic fixture. The passage string is invented for this test and
    /// is also planted inside the surrounding paragraphs, which is how a
    /// real selection window contains the selection.
    @MainActor
    func testOutgoingPromptContainsThePassageBeforeTheChipIsDismissedAndNotAfter() async throws {
        let passage = "SYNTHETIC PASSAGE FIXTURE 148: the selected sentence stays out after dismiss."
        let surrounding = "Nearby synthetic paragraphs. \(passage) The paragraph after the selection stays."
        let title = "Synthetic Notes"
        let assistant = PromptCaptureAssistant()
        let model = SelectionThreadViewModel(assistant: assistant)
        var chip = PinnedPassageChip()
        let pinned = PinnedPassage(pageIndex: 38, excerpt: passage, fingerprint: "fixture-148", bounds: nil)
        XCTAssertTrue(chip.noteSelection(pinned))

        model.updateSelection(
            TextSelectionContext(
                pageIndex: 38,
                selectedText: passage,
                surroundingText: surrounding,
                fingerprint: pinned.fingerprint,
                bounds: nil,
                lines: nil
            ),
            documentTitle: title,
            existingHighlights: []
        )

        try await model.sendMessage(
            "What does this show?",
            documentTitle: title,
            passage: chip.messagePassage
        ) { _ in }
        let before = try outgoingPrompt(
            context: XCTUnwrap(assistant.contexts.last),
            question: "What does this show?",
            retrieval: XCTUnwrap(assistant.retrievals.last)
        )
        XCTAssertTrue(before.contains(passage))
        XCTAssertEqual(assistant.contexts.count, 1, "A question sent while the chip is showing keeps the session")

        try await model.sendMessage(
            "Ask again while it is pinned.",
            documentTitle: title,
            passage: chip.messagePassage
        ) { _ in }
        XCTAssertEqual(assistant.contexts.count, 1)
        XCTAssertTrue(try outgoingPrompt(
            context: XCTUnwrap(assistant.contexts.last),
            question: "Ask again while it is pinned.",
            retrieval: XCTUnwrap(assistant.retrievals.last)
        ).contains(passage))

        chip.dismiss()
        XCTAssertNil(chip.messagePassage)
        model.omitSelectedPassageFromPrompt(documentTitle: title)
        let dismissedContext = try XCTUnwrap(assistant.contexts.last)
        XCTAssertFalse(
            ReadingPromptBuilder.instructions(for: dismissedContext).contains(passage),
            "× removes the passage from the session before the next question"
        )

        try await model.sendMessage(
            "What remains in view?",
            documentTitle: title,
            passage: chip.messagePassage
        ) { _ in }
        let after = try outgoingPrompt(
            context: XCTUnwrap(assistant.contexts.last),
            question: "What remains in view?",
            retrieval: XCTUnwrap(assistant.retrievals.last)
        )
        XCTAssertFalse(after.contains(passage))
        XCTAssertTrue(after.contains("The paragraph after the selection stays."))
        XCTAssertTrue(after.contains("[[CAUCHY_BASIS: PDF]]"))
        XCTAssertEqual(assistant.contexts.count, 2, "The question after × reuses the session × installed")
        XCTAssertNil(model.activeThread?.messages.last(where: { $0.role == .user })?.passage)

        let broughtBack = "A different synthetic sentence brings the passage back."
        XCTAssertTrue(chip.noteSelection(
            PinnedPassage(pageIndex: 4, excerpt: broughtBack, fingerprint: "fixture-149", bounds: nil)
        ))
        model.updateSelection(
            TextSelectionContext(
                pageIndex: 4,
                selectedText: broughtBack,
                surroundingText: "Other synthetic paragraphs.",
                fingerprint: "fixture-149",
                bounds: nil,
                lines: nil
            ),
            documentTitle: title,
            existingHighlights: []
        )
        let restored = ReadingPromptBuilder.instructions(for: try XCTUnwrap(assistant.contexts.last))
        XCTAssertTrue(restored.contains(broughtBack))
        XCTAssertFalse(restored.contains(passage))

        chip.dismiss()
        let saved = Highlight(pageIndex: 38, selectedText: passage, surroundingText: surrounding)
        XCTAssertTrue(chip.noteSelection(pinned, explicit: true))
        model.restoreThread(from: saved, documentTitle: title)
        let fromHighlight = ReadingPromptBuilder.instructions(for: try XCTUnwrap(assistant.contexts.last))
        XCTAssertTrue(fromHighlight.contains(passage))
        XCTAssertEqual(chip.messagePassage?.excerpt, passage)
    }

    /// The same assembly the reading assistants use: session instructions,
    /// then the ask-time blocks, then the question. Retrieval stays empty
    /// for this fixture; the passage is only in the selected-text block.
    private func outgoingPrompt(
        context: ReadingContext,
        question: String,
        retrieval: AskRetrieval
    ) -> String {
        var prompt = ReadingPromptBuilder.instructions(for: context)
        let budgets = ReadingPromptBuilder.evidenceBudgets(for: .onDevice)
        if let block = ReadingPromptBuilder.referencedStatementsBlock(
            retrieval.statements,
            characterBudget: budgets.statements
        ) {
            prompt += "\n\n" + block
        }
        if let block = ReadingPromptBuilder.retrievedPassagesBlock(
            retrieval.passages,
            characterBudget: budgets.passages
        ) {
            prompt += "\n\n" + block
        }
        if let block = ReadingPromptBuilder.citableSourcesBlock(retrieval.citableSources) {
            prompt += "\n\n" + block
        }
        return prompt + "\n\n" + question
    }

    func testOlderMessagesDecodeWithoutAPassage() throws {
        let legacy = ThreadMessage(role: .user, content: "why?")
        let data = try JSONEncoder().encode(legacy)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["passage"])

        let decoded = try JSONDecoder().decode(ThreadMessage.self, from: data)
        XCTAssertNil(decoded.passage)
        XCTAssertEqual(decoded.content, "why?")

        let sent = ThreadMessage(
            role: .user,
            content: "What does this show?",
            passage: MessagePassage(
                pageIndex: 38,
                excerpt: "By taking complements, one can show the following."
            )
        )
        let roundTrip = try JSONDecoder().decode(ThreadMessage.self, from: try JSONEncoder().encode(sent))
        XCTAssertEqual(roundTrip.passage?.pageIndex, 38)
        XCTAssertEqual(roundTrip.passage?.pinned.line, "p. 39 · By taking complements, one can show the following.")
    }

    private func samplePassage(_ excerpt: String, page: Int, fingerprint: String) -> PinnedPassage {
        PinnedPassage(pageIndex: page, excerpt: excerpt, fingerprint: fingerprint, bounds: nil)
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

@MainActor
private final class PromptCaptureAssistant: ReadingAssistantProtocol {
    let provider = AssistantConnectorID.onDevice
    let availability = ReadingAssistantAvailability.available(.onDevice)
    var isResponding = false
    private(set) var contexts: [ReadingContext] = []
    private(set) var retrievals: [AskRetrieval] = []

    func resetSession(context: ReadingContext) {
        contexts.append(context)
    }

    func restoreSession(context: ReadingContext, messages: [ThreadMessage]) {
        contexts.append(context)
    }

    func ask(
        question: String,
        retrieval: AskRetrieval,
        onPartial: ((String) -> Void)?
    ) async throws -> String {
        retrievals.append(retrieval)
        return "Synthetic reply.\n[[CAUCHY_BASIS: INSUFFICIENT]]"
    }
}
