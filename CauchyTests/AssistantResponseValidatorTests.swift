import AppKit
import PDFKit
import XCTest
@testable import Cauchy

final class AssistantResponseValidatorTests: XCTestCase {
    func testEvidenceBoundaryParsesAndHidesValidTrailer() {
        let parsed = AssistantAnswerBoundary.parse("A claim from the notes.\n\n[[CAUCHY_BASIS: PDF]]")

        XCTAssertEqual(parsed.content, "A claim from the notes.")
        XCTAssertEqual(parsed.basis, .pdf)
    }

    func testEvidenceBoundaryDoesNotTrustInvalidOrMissingTrailer() {
        let invalid = AssistantAnswerBoundary.parse("A claim.\n[[CAUCHY_BASIS: MAYBE]]")
        let missing = AssistantAnswerBoundary.parse("A claim.")

        XCTAssertEqual(invalid.content, "A claim.")
        XCTAssertEqual(invalid.basis, .unverified)
        XCTAssertEqual(missing.content, "A claim.")
        XCTAssertEqual(missing.basis, .unverified)
    }

    func testStreamingEvidenceBoundaryNeverShowsControlMarker() {
        XCTAssertEqual(
            AssistantAnswerBoundary.displayContent("A claim.\n[[CAUCHY_BASIS: MI"),
            "A claim."
        )
    }

    func testLegacyThreadMessageDecodesWithoutEvidenceMetadata() throws {
        let data = Data(#"{"id":"00000000-0000-0000-0000-000000000001","role":"assistant","content":"legacy","createdAt":0}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let message = try decoder.decode(ThreadMessage.self, from: data)

        XCTAssertEqual(message.content, "legacy")
        XCTAssertNil(message.answerEvidence)
    }

    func testAnswerSourceLocationSurvivesWorkspaceEncoding() throws {
        let anchor = AnswerSourceAnchor(
            label: "Theorem 2.1",
            pageIndex: 6,
            region: NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.04),
            sourceID: "R1"
        )
        let message = ThreadMessage(
            role: .assistant,
            content: "An answer.",
            answerEvidence: AnswerEvidence(
                basis: .pdf,
                sourcePages: [7],
                referencedStatementCount: 1,
                retrievedPassageCount: 0,
                providerID: "onDevice",
                sourceAnchors: [anchor],
                citationStatus: .idsResolve,
                citedSourceIDs: ["R1"],
                declaredBasis: .pdf
            )
        )

        let decoded = try JSONDecoder().decode(ThreadMessage.self, from: JSONEncoder().encode(message))
        XCTAssertEqual(decoded.answerEvidence?.sourceAnchors, [anchor])
        XCTAssertEqual(decoded.answerEvidence?.citationStatus, .idsResolve)
        XCTAssertEqual(decoded.answerEvidence?.citedSourceIDs, ["R1"])
    }

    func testPreviouslySavedAnswerEvidenceDecodesWithoutSourceLocations() throws {
        let data = Data(#"{"basis":"pdf","sourcePages":[2],"referencedStatementCount":1,"retrievedPassageCount":0,"providerID":"onDevice"}"#.utf8)

        let evidence = try JSONDecoder().decode(AnswerEvidence.self, from: data)

        XCTAssertNil(evidence.sourceAnchors)
        XCTAssertNil(evidence.citationStatus)
        XCTAssertEqual(evidence.sourcePages, [2])
    }

    func testReadingPromptRequiresAnExplicitEvidenceBoundary() {
        let prompt = ReadingPromptBuilder.instructions(for: ReadingContext(
            documentTitle: "Notes",
            selectedText: "A statement",
            surroundingText: "Nearby proof",
            retrievedPassages: []
        ))

        XCTAssertTrue(prompt.contains("[[CAUCHY_BASIS: PDF]]"))
        XCTAssertTrue(prompt.contains("[[CAUCHY_BASIS: MIXED]]"))
        XCTAssertTrue(prompt.contains("[[CAUCHY_BASIS: INSUFFICIENT]]"))
        XCTAssertTrue(prompt.contains("do not guess"))
        XCTAssertTrue(prompt.contains("immediately after each material claim"))
    }

    func testCitationAuditChecksOnlyIDsActuallyResolvedByCauchy() {
        let sources = [AnswerSourceAnchor(
            label: "Selected passage",
            pageIndex: 0,
            region: NormalizedRect(x: 0.1, y: 0.2, width: 0.4, height: 0.1),
            sourceID: "S1"
        )]

        XCTAssertEqual(AnswerCitationAudit.evaluate("A PDF claim. [S1]", sources: sources).status, .idsResolve)
        XCTAssertEqual(AnswerCitationAudit.evaluate("A claim. [P2]", sources: sources).status, .invalidID)
        XCTAssertEqual(AnswerCitationAudit.evaluate("A claim.", sources: sources).status, .noResolvableCitation)
        XCTAssertEqual(AnswerCitationAudit.evaluate(
            "A claim from the page. [S1]\n\nA second uncited claim from the page.",
            sources: sources
        ).status, .uncitedPassage)
        XCTAssertEqual(AnswerCitationAudit.evaluate(
            "1. The first result\n\nA claim from the page. [S1]",
            sources: sources
        ).status, .idsResolve)
        XCTAssertEqual(AnswerCitationAudit.evaluate(
            "Points:\n- First claim. [S1]\n- Second claim.",
            sources: sources
        ).status, .uncitedPassage)
        XCTAssertEqual(AnswerCitationAudit.evaluate("A claim. [s1] [S1]", sources: sources).citedSourceIDs, ["S1"])
    }

    func testPromptCatalogListsOnlyResolvedSourceIDs() {
        let source = AnswerSourceAnchor(
            label: "Theorem 1.2",
            pageIndex: 4,
            region: NormalizedRect(x: 0.1, y: 0.2, width: 0.4, height: 0.1),
            sourceID: "R1"
        )
        let block = ReadingPromptBuilder.citableSourcesBlock([source])

        XCTAssertTrue(block?.contains("[R1] Theorem 1.2, PDF p. 5") == true)
        XCTAssertNil(ReadingPromptBuilder.citableSourcesBlock([]))
    }

    @MainActor
    func testThreadPersistsCleanAnswerAndAuditableBasis() async throws {
        let viewModel = SelectionThreadViewModel(assistant: EvidenceBoundaryAssistantStub())
        viewModel.updateSelection(
            TextSelectionContext(
                pageIndex: 4,
                selectedText: "A statement",
                surroundingText: "Nearby proof",
                fingerprint: "fixture",
                bounds: nil,
                lines: nil
            ),
            documentTitle: "Notes",
            existingHighlights: []
        )

        try await viewModel.sendMessage("Why?", documentTitle: "Notes") { _ in }
        let answer = try XCTUnwrap(viewModel.activeThread?.messages.last)

        XCTAssertEqual(answer.content, "Because the supplied statement says so.")
        XCTAssertEqual(answer.answerEvidence?.basis, .unverified)
        XCTAssertEqual(answer.answerEvidence?.declaredBasis, .pdf)
        XCTAssertEqual(answer.answerEvidence?.citationStatus, .noResolvableCitation)
        XCTAssertEqual(answer.answerEvidence?.sourcePages, [5])
        XCTAssertEqual(answer.answerEvidence?.providerID, AssistantConnectorID.onDevice.rawValue)
    }

    @MainActor
    func testOutsideKnowledgeAnswerKeepsMixedBoundaryWithoutPDFCitation() async throws {
        let assistant = EvidenceBoundaryAssistantStub(
            response: "The standard account goes beyond this excerpt.\n[[CAUCHY_BASIS: MIXED]]"
        )
        let viewModel = SelectionThreadViewModel(assistant: assistant)
        viewModel.updateSelection(
            TextSelectionContext(
                pageIndex: 0,
                selectedText: "A short excerpt",
                surroundingText: "",
                fingerprint: "fixture",
                bounds: nil,
                lines: nil
            ),
            documentTitle: "Notes",
            existingHighlights: []
        )

        try await viewModel.sendMessage("Explain", documentTitle: "Notes") { _ in }

        XCTAssertEqual(viewModel.activeThread?.messages.last?.answerEvidence?.basis, .mixed)
        XCTAssertEqual(viewModel.activeThread?.messages.last?.answerEvidence?.citationStatus, .noResolvableCitation)
    }

    @MainActor
    func testThreadDoesNotAcceptSelectedRegionWithoutMatchingPDFText() async throws {
        let viewModel = SelectionThreadViewModel(assistant: EvidenceBoundaryAssistantStub())
        let document = PDFDocument()
        let image = NSImage(size: NSSize(width: 100, height: 100), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            return true
        }
        document.insert(try XCTUnwrap(PDFPage(image: image)), at: 0)
        viewModel.pdfDocument = document
        let region = NormalizedRect(x: 0.15, y: 0.4, width: 0.2, height: 0.05)
        viewModel.updateSelection(
            TextSelectionContext(
                pageIndex: 0,
                selectedText: "A statement",
                surroundingText: "Nearby proof",
                fingerprint: "fixture",
                bounds: region,
                lines: nil
            ),
            documentTitle: "Notes",
            existingHighlights: []
        )

        try await viewModel.sendMessage("Why?", documentTitle: "Notes") { _ in }
        XCTAssertEqual(viewModel.activeThread?.messages.last?.answerEvidence?.sourceAnchors, [])
        XCTAssertEqual(viewModel.activeThread?.messages.last?.answerEvidence?.basis, .unverified)
    }

    @MainActor
    func testAnswerProvenanceOmitsPassageDroppedFromModelPrompt() async throws {
        let assistant = EvidenceBoundaryAssistantStub()
        let viewModel = SelectionThreadViewModel(assistant: assistant)
        viewModel.documentIndex = LongPassageIndexStub()
        viewModel.updateSelection(
            TextSelectionContext(
                pageIndex: 4,
                selectedText: "A statement",
                surroundingText: "Nearby proof",
                fingerprint: "fixture",
                bounds: nil,
                lines: nil
            ),
            documentTitle: "Notes",
            existingHighlights: []
        )

        try await viewModel.sendMessage("Why?", documentTitle: "Notes") { _ in }
        let evidence = try XCTUnwrap(viewModel.activeThread?.messages.last?.answerEvidence)

        XCTAssertEqual(assistant.lastRetrieval?.passages.count, 2)
        XCTAssertEqual(evidence.sourcePages, [5, 9, 10])
        XCTAssertEqual(evidence.retrievedPassageCount, 2)
    }

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

    /// A line that already contains `$` used to skip `wrapBareMath`, so the
    /// neighboring `\frac` was a `Text` run. A lone `\gamma` was one weak
    /// command and never delimited at all.
    func testLooseGammaAndNeighboringFractionLeaveNoRawTeX() {
        let raw = "Let \\gamma be a closed curve where $n$ satisfies \\frac{1}{2\\pi i}."
        let normalized = AssistantResponseNormalizer.normalize(raw)
        XCTAssertFalse(AssistantResponseValidator.hasUndelimitedLaTeX(normalized))
        XCTAssertTrue(normalized.contains("$\\gamma$") || normalized.contains("$\\gamma "))

        let dump = ReferenceMathRendering.plainTextDump(of: raw)
        XCTAssertTrue(dump.contains("closed curve"))
        XCTAssertFalse(dump.contains("\\"))
        XCTAssertFalse(dump.contains("$"))
        XCTAssertFalse(dump.contains("\\frac"))

        let math = ReferenceMathRendering.mathSources(of: raw)
        XCTAssertTrue(math.contains { $0.contains("\\gamma") })
        XCTAssertTrue(math.contains { $0.contains("\\frac") })
    }

    func testBeginAlignIsDelimitedAndNotPlainText() {
        let raw = "\\begin{align}\n\\int_{\\gamma} \\frac{dz}{z} &= 2\\pi i\n\\end{align}"
        let dump = ReferenceMathRendering.plainTextDump(of: raw)
        XCTAssertFalse(dump.contains("\\begin{"))
        XCTAssertFalse(dump.contains("\\frac"))
        XCTAssertFalse(dump.contains("$"))
        XCTAssertFalse(dump.contains("\\"))
        let sources = ReferenceMathRendering.mathSources(of: raw)
        XCTAssertEqual(sources.count, 1)
        XCTAssertTrue(sources[0].contains("\\begin{align}"))
        XCTAssertTrue(sources[0].contains("\\int"))
        XCTAssertTrue(sources[0].contains("\\frac"))
        XCTAssertTrue(sources[0].contains("\\end{align}"))
    }

    /// The reference card turns each JSON `\n` into a blank line before
    /// normalizing. Those interior lines must stay inside the one align
    /// source. `$n$` is the variable in "where $n$ satisfies", not a fragment
    /// of the environment.
    func testUnescapedAlignStaysOneMathSource() {
        let raw = "Let \\gamma be a closed curve where $n$ satisfies \\frac{1}{2\\pi i}.\\n\\begin{align}\\n\\label{eq:sample}\\n\\int_{\\gamma} \\frac{dz}{z} &= 2\\pi i\\n\\end{align}\\nMoreover **$\\frac{1}{2}$** is the residue."
        let text = ReferencePreviewPresentation.statementText(from: raw)
        XCTAssertTrue(text.contains("\n"))
        XCTAssertFalse(text.contains("\\n"))

        let dump = ReferenceMathRendering.plainTextDump(of: text)
        XCTAssertTrue(dump.contains("where"))
        XCTAssertTrue(dump.contains("satisfies"))
        XCTAssertTrue(dump.contains("Moreover"))
        XCTAssertTrue(dump.contains("residue"))
        XCTAssertFalse(dump.contains("\\"))
        XCTAssertFalse(dump.contains("$"))

        let sources = ReferenceMathRendering.mathSources(of: text)
        XCTAssertTrue(sources.contains { $0 == "n" })
        let fragments = sources.filter { source in
            source == "\\end{align}" || (source.hasPrefix("\\begin{align}") && !source.contains("\\int"))
        }
        XCTAssertEqual(fragments, [])
        guard let align = sources.first(where: { $0.contains("\\begin{align}") }) else {
            return XCTFail("align environment was not one math source: \(sources)")
        }
        XCTAssertTrue(align.contains("\\label"))
        XCTAssertTrue(align.contains("\\int"))
        XCTAssertTrue(align.contains("\\frac"))
        XCTAssertTrue(align.contains("\\end{align}"))
    }

    func testBoldWrappedFractionIsMathNotText() {
        let raw = "Moreover **$\\frac{1}{2}$** is the residue."
        let dump = ReferenceMathRendering.plainTextDump(of: raw)
        XCTAssertTrue(dump.contains("Moreover"))
        XCTAssertTrue(dump.contains("residue"))
        XCTAssertFalse(dump.contains("$"))
        XCTAssertFalse(dump.contains("\\"))
        XCTAssertFalse(dump.contains("\\frac"))
        XCTAssertTrue(ReferenceMathRendering.mathSources(of: raw).contains { $0.contains("\\frac") })
    }

    /// `C:\Users` is one uppercase command and must stay prose. Two lowercase
    /// commands on an otherwise bare line are still wrapped by `wrapBareMath`.
    func testSingleUppercaseBackslashWordStaysProse() {
        let raw = "See C:\\Users for the notes."
        let normalized = AssistantResponseNormalizer.normalize(raw)
        XCTAssertFalse(normalized.contains("$"))
        XCTAssertTrue(normalized.contains("\\Users"))
        XCTAssertFalse(ReferenceMathRendering.needsTypesetting(raw))
    }

    func testAlignEnvironmentTypesetsWithoutUnknownBegin() {
        let latex = "\\begin{align}\n\\label{eq:sample}\n\\int_{\\gamma} \\frac{dz}{z} &= 2\\pi i\n\\end{align}"
        guard let rendered = LaTeXValidator.renderableLatex(from: latex) else {
            return XCTFail("align did not typeset")
        }
        XCTAssertTrue(rendered.contains("\\frac"))
        XCTAssertFalse(rendered.contains("\\label"))
        XCTAssertFalse(Self.renderedStillHasRawAlign(rendered))
        XCTAssertTrue(rendered.contains("\\begin{aligned}") || !rendered.contains("\\begin{"))
    }

    /// `\begin{aligned}` contains the character sequence `\begin{align}`.
    private static func renderedStillHasRawAlign(_ latex: String) -> Bool {
        var rest = latex[...]
        while let range = rest.range(of: "\\begin{") {
            let name = rest[range.upperBound...]
            if name.hasPrefix("align}") || name.hasPrefix("align*") {
                return true
            }
            rest = name
        }
        return false
    }

    /// `\rightarrow` contains the letters of `\right`. That substring used to
    /// promote a short `$…$` formula onto its own centred line.
    func testInlineArrowStaysInline() {
        let samples = [
            "A bounded entire function $f : \\mathbb{C} \\rightarrow \\mathbb{C}$ is constant.",
            "and suppose that $f : U \\setminus \\{z_0\\} \\rightarrow \\mathbb{C}$ is holomorphic.",
        ]
        for sample in samples {
            let blocks = MessageContentParser.blocks(from: MessageContentParser.parse(sample))
            XCTAssertFalse(blocks.contains { block in
                if case .displayMath = block { return true }
                return false
            }, sample)
            guard case .inlineLine(let line) = blocks.first else {
                return XCTFail("expected one inline line for \(sample)")
            }
            XCTAssertTrue(line.contains { segment in
                if case .inlineMath(let latex) = segment { return latex.contains("\\rightarrow") }
                return false
            }, sample)
            let prose = line.compactMap { segment -> String? in
                if case .text(let value) = segment { return value }
                return nil
            }.joined()
            XCTAssertFalse(prose.trimmingCharacters(in: .whitespaces).isEmpty, sample)
        }
        XCTAssertFalse(LaTeXNormalizer.shouldRenderAsDisplayMath("f : \\mathbb{C} \\rightarrow \\mathbb{C}"))
        XCTAssertTrue(LaTeXNormalizer.shouldRenderAsDisplayMath("\\left| x \\right|"))
        XCTAssertTrue(LaTeXNormalizer.containsCommand("\\left| x \\right|", "\\right"))
        XCTAssertFalse(LaTeXNormalizer.containsCommand("\\rightarrow", "\\right"))
    }

    func testInlinePunctuationStaysWithTheMathBeforeIt() throws {
        let content = "on an open set $U$, then $f(U)$ is open."
        let blocks = MessageContentParser.blocks(from: MessageContentParser.parse(content))
        guard case .inlineLine(let line) = blocks.first else {
            return XCTFail("expected an inline line, got \(blocks)")
        }
        let tokens = MessageContentParser.flowTokens(from: line)
        let glued = MessageContentParser.keepsWithPreviousMath(tokens)
        let comma = tokens.firstIndex { segment in
            if case .text(let value) = segment { return value.hasPrefix(",") }
            return false
        }
        let word = tokens.firstIndex { segment in
            if case .text(let value) = segment { return value.hasPrefix("then") }
            return false
        }
        let commaIndex = try XCTUnwrap(comma)
        let wordIndex = try XCTUnwrap(word)
        XCTAssertTrue(glued[commaIndex], "the comma can start the next line")
        XCTAssertTrue(glued[wordIndex], "the word after the comma can split from the math")
        XCTAssertGreaterThan(commaIndex, 0)
        if case .inlineMath = tokens[commaIndex - 1] {
        } else {
            XCTFail("comma is not attached to the math before it")
        }
    }

    func testDisplayLineTakesPunctuationOnly() {
        let cases: [(raw: String, mark: String, following: String)] = [
            (
                "The first two coefficients vanish.\n$$a_0 = a_1 = 0$$\n, then the constant term is zero.",
                ",",
                "then the constant term is zero."
            ),
            (
                "Hence \\[a_0 = 0\\], so the rest follows.",
                ",",
                "so the rest follows."
            ),
            (
                "We have \\begin{equation}a_0 = 0\\end{equation}. The series stops.",
                ".",
                "The series stops."
            ),
            (
                "Compare $$x = 1$$: the two sides agree.",
                ":",
                "the two sides agree."
            ),
            (
                "Stop.\n$$a_0 = 0$$\n;",
                ";",
                ""
            ),
        ]
        for (raw, mark, following) in cases {
            let blocks = MessageContentParser.blocks(
                from: MessageContentParser.parseNormalized(LaTeXNormalizer.normalizeForDisplay(raw))
            )
            guard let displayIndex = blocks.firstIndex(where: { block in
                if case .displayMath = block { return true }
                return false
            }), case .displayMath(let latex, let trailing) = blocks[displayIndex] else {
                XCTFail("no display equation in \(raw)")
                continue
            }
            XCTAssertTrue(latex.contains("a_0") || latex.contains("x = 1"), raw)
            XCTAssertEqual(trailing, mark, raw)
            XCTAssertFalse(trailing.contains { $0.isLetter }, "the next word joined the display line: \(raw)")
            let prose = displayIndex + 1 < blocks.count ? proseOpening(blocks[displayIndex + 1]) : ""
            XCTAssertEqual(prose, following, raw)
            XCTAssertFalse(prose.hasPrefix(mark), raw)
        }
    }

    private func proseOpening(_ block: MessageBlock) -> String {
        switch block {
        case .text(let value):
            return value
        case .inlineLine(let segments):
            guard case .text(let value) = segments.first else { return "" }
            return value.trimmingCharacters(in: .whitespaces)
        case .displayMath:
            return ""
        }
    }

    func testPunctuationAfterADisplayEquationStaysOnThatEquation() {
        let raw = "The first two coefficients vanish.\n$$a_0 = a_1 = 0$$\n, so the constant term is zero."
        let blocks = MessageContentParser.blocks(
            from: MessageContentParser.parseNormalized(LaTeXNormalizer.normalizeForDisplay(raw))
        )
        let display = blocks.compactMap { block -> (String, String)? in
            if case .displayMath(let latex, let trailing) = block { return (latex, trailing) }
            return nil
        }
        XCTAssertEqual(display.count, 1)
        XCTAssertTrue(display[0].0.contains("a_0"))
        XCTAssertEqual(display[0].1, ",")
        XCTAssertFalse(display[0].1.contains("so"))
        let following = blocks.drop { block in
            if case .displayMath = block { return false }
            return true
        }.dropFirst()
        XCTAssertTrue(following.contains { block in
            if case .text(let value) = block {
                return value.hasPrefix("so ") && value.contains("the constant term is zero")
            }
            if case .inlineLine(let segments) = block, case .text(let value) = segments.first {
                let trimmed = value.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("so ") && trimmed.contains("the constant term is zero")
            }
            return false
        })
    }
}

private final class EvidenceBoundaryAssistantStub: ReadingAssistantProtocol {
    let provider = AssistantConnectorID.onDevice
    let availability = ReadingAssistantAvailability.available(.onDevice)
    var isResponding = false
    var lastRetrieval: AskRetrieval?
    let response: String

    init(response: String = "Because the supplied statement says so.\n[[CAUCHY_BASIS: PDF]]") {
        self.response = response
    }

    func resetSession(context: ReadingContext) {}
    func restoreSession(context: ReadingContext, messages: [ThreadMessage]) {}

    func ask(
        question: String,
        retrieval: AskRetrieval,
        onPartial: ((String) -> Void)?
    ) async throws -> String {
        lastRetrieval = retrieval
        onPartial?("Because the supplied statement says so.\n[[CAUCHY_BASIS: P")
        return response
    }
}

private struct LongPassageIndexStub: DocumentIndexProtocol {
    func passages(matching query: String, limit: Int, excludingPage: Int?) -> [String] {
        (9...11).map { page in "[p. \(page)] " + String(repeating: "a", count: 500) }
    }
}
