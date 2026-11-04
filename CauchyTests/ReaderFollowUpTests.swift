import XCTest
@testable import Cauchy

/// Synthetic statements only. Nothing here is copied from a paper, a holdout,
/// or the scorecard set.
final class ReaderFollowUpTests: XCTestCase {
    func testProofAndNextResultAreTheTwoFollowUps() {
        let followUps = ReaderFollowUps.suggest(
            answer: "A continuous image of a closed interval is connected. [R1]",
            anchors: [anchor("R1", label: "Proposition 5.3")],
            statements: notes
        )

        XCTAssertEqual(followUps.count, 2)
        XCTAssertEqual(
            followUps.map(\.question),
            [
                "Why does the proof of Proposition 5.3 need compactness?",
                "What does Theorem 5.4 build on?",
            ]
        )
        XCTAssertEqual(followUps[0].pageLabel, "41")
        XCTAssertEqual(followUps[0].pageIndex, 40)
        XCTAssertEqual(followUps[1].pageLabel, "47")
        XCTAssertEqual(followUps[1].pageIndex, 46)
        XCTAssertTrue(followUps.allSatisfy { !ReaderFollowUps.isGeneric($0.question) })
    }

    func testNoFollowUpWhenTheAnswerCitesNothingInTheDocument() {
        let followUps = ReaderFollowUps.suggest(
            answer: "The selected sentence does not name a result.",
            anchors: [anchor("P1", label: "Retrieved passage")],
            statements: notes
        )

        XCTAssertTrue(followUps.isEmpty)
    }

    func testANumberTheDocumentDoesNotContainIsNotAFollowUp() {
        let followUps = ReaderFollowUps.suggest(
            answer: "Theorem 9.9 would settle this, but it is not in these notes.",
            statements: notes
        )

        XCTAssertTrue(followUps.isEmpty)
    }

    func testDefinitionUsedByTheStatementIsOfferedWhenNothingElseIs() {
        let proposition = statement(
            .proposition, "1.1",
            page: 4,
            text: "Every nonempty finite set has a least element by Definition 2.1."
        )
        let definition = statement(
            .definition, "2.1",
            name: "Least element",
            page: 3,
            text: "A least element of a set is a member that precedes every other member."
        )

        let followUps = ReaderFollowUps.suggest(
            answer: "Proposition 1.1 applies Definition 2.1 to a finite set.",
            statements: [proposition, definition]
        )

        XCTAssertEqual(followUps.map(\.question), ["What does the definition of least element require?"])
        XCTAssertEqual(followUps.first?.pageLabel, "4")
    }

    func testExerciseQuotesTheAssignmentItPrints() {
        let proposition = statement(
            .proposition, "2.2",
            page: 8,
            text: "A monotone bounded sequence converges."
        )
        let exercise = statement(
            .exercise, "2.4",
            page: 9,
            text: "Apply Proposition 2.2 to f(x) = 1/x on the half-line."
        )

        let followUps = ReaderFollowUps.suggest(
            answer: "Proposition 2.2 says a monotone bounded sequence converges.",
            statements: [proposition, exercise]
        )

        XCTAssertEqual(followUps.map(\.question), ["Try it on f(x) = 1/x."])
        XCTAssertEqual(followUps.first?.pageIndex, 9)
    }

    func testAlreadyAskedQuestionIsDropped() {
        let followUps = ReaderFollowUps.suggest(
            answer: "A continuous image of a closed interval is connected.",
            anchors: [anchor("R1", label: "Proposition 5.3")],
            statements: notes,
            alreadyAsked: [
                "Why does the proof of Proposition 5.3 need compactness?",
                "What does Theorem 5.4 build on?",
            ]
        )

        XCTAssertTrue(followUps.isEmpty)
    }

    func testAnswerThatAlreadyGivesTheProofDoesNotRepeatIt() {
        let followUps = ReaderFollowUps.suggest(
            answer: "The proof of Proposition 5.3 needs compactness of the domain, and Theorem 5.4 builds on that.",
            anchors: [anchor("R1", label: "Proposition 5.3")],
            statements: notes
        )

        XCTAssertEqual(
            followUps.map(\.question),
            ["What does the definition of compactness require?"]
        )
        XCTAssertEqual(followUps.first?.pageLabel, "13")
    }

    func testFollowUpVoiceOverIsTheQuestionOnly() {
        let followUps = ReaderFollowUps.suggest(
            answer: "A continuous image of a closed interval is connected. [R1]",
            anchors: [anchor("R1", label: "Proposition 5.3")],
            statements: notes
        )

        XCTAssertEqual(followUps[0].pageLabel, "41")
        XCTAssertEqual(followUps[0].voiceOverLabel, followUps[0].question)
        XCTAssertFalse(followUps[0].voiceOverLabel.localizedCaseInsensitiveContains("page"))
    }

    func testFollowUpsStayOnTheLatestAnswerOnly() {
        let earlier = ThreadMessage(role: .assistant, content: "The earlier answer.")
        let latest = ThreadMessage(role: .assistant, content: "The latest answer.")
        let question = ThreadMessage(role: .user, content: "And what about the next one?")

        XCTAssertFalse(ConversationFollowUps.shouldShow(on: earlier, in: [earlier, latest], isResponding: false))
        XCTAssertTrue(ConversationFollowUps.shouldShow(on: latest, in: [earlier, latest], isResponding: false))
        XCTAssertFalse(ConversationFollowUps.shouldShow(on: latest, in: [earlier, latest, question], isResponding: false))
        XCTAssertFalse(ConversationFollowUps.shouldShow(on: latest, in: [earlier, latest], isResponding: true))
        XCTAssertFalse(ConversationFollowUps.shouldShow(on: question, in: [earlier, latest, question], isResponding: false))
    }

    func testAtMostTwoEvenWhenMoreGroundedStepsExist() {
        let exercise = statement(
            .exercise, "5.5",
            page: 48,
            text: "Check Proposition 5.3 on f(x) = 1/x."
        )
        let followUps = ReaderFollowUps.suggest(
            answer: "By Proposition 5.3 the image is connected.",
            statements: notes + [exercise]
        )

        XCTAssertEqual(followUps.count, 2)
        XCTAssertEqual(followUps[0].question, "Why does the proof of Proposition 5.3 need compactness?")
        XCTAssertEqual(followUps[1].question, "What does Theorem 5.4 build on?")
    }

    func testProofTextStopsBeforeTheNextResult() {
        let page = """
        Proposition 5.3. A closed interval is connected.
        Proof. The argument uses compactness of the domain.
        Theorem 5.4. The components are open.
        """
        let heading = "Proposition 5.3"
        let end = (page as NSString).range(of: heading).location + (heading as NSString).length
        let proof = ReaderFollowUpCatalog.proof(in: page, pageIndex: 40, afterUTF16: end)

        XCTAssertEqual(proof?.text, "The argument uses compactness of the domain.")
        XCTAssertEqual(proof?.pageIndex, 40)
        XCTAssertEqual(proof?.headingText, "Proof")
        XCTAssertFalse(proof?.text.contains("Theorem") ?? true)
    }

    func testProofOnTheFollowingPageIsKept() {
        let page = "Proposition 5.3. A closed interval is connected.\n"
        let next = "Proof. The argument uses compactness of the domain.\nTheorem 5.4. Later.\n"
        let end = (page as NSString).length
        let proof = ReaderFollowUpCatalog.proof(in: page, pageIndex: 2, afterUTF16: end, nextPage: next)

        XCTAssertEqual(proof?.text, "The argument uses compactness of the domain.")
        XCTAssertEqual(proof?.pageIndex, 3)
    }

    func testCatalogDropsAnUnverifiedTranscript() {
        let page = PageText(pageIndex: 0, text: "Definition 1.1. A widget is a finite nonempty set.\n")
        let grounded = block(
            .definition, "1.1",
            page: 0,
            excerpt: "A widget is a finite nonempty set.",
            matched: "Definition 1.1",
            origin: .sourceFallback
        )
        let ocr = block(
            .definition, "9.9",
            page: 0,
            excerpt: "An unverified line the model guessed.",
            matched: "Definition 9.9",
            origin: .ocrCandidate,
            source: .visionOCR
        )

        let statements = ReaderFollowUpCatalog.statements(from: [grounded, ocr], pages: [page])

        XCTAssertEqual(statements.map(\.reference.number), ["1.1"])
    }

    func testAMentionOfProofInsideASentenceIsNotAProof() {
        let page = "Proposition 1.1. See the proof in the appendix for the rest of this construction today.\n"
        let end = (page as NSString).range(of: "Proposition 1.1").location + ("Proposition 1.1" as NSString).length
        XCTAssertNil(ReaderFollowUpCatalog.proof(in: page, pageIndex: 0, afterUTF16: end))
    }

    private var notes: [ReaderFollowUpStatement] {
        [
            statement(
                .definition, "1.4",
                name: "Compactness",
                page: 12,
                text: "A set is compact when every open cover has a finite subcover."
            ),
            statement(
                .proposition, "5.3",
                page: 40,
                text: "A continuous image of a closed interval is connected.",
                proof: "The argument uses compactness of the domain to take a finite subcover."
            ),
            statement(
                .theorem, "5.4",
                page: 46,
                text: "The components of a locally connected space are open."
            ),
        ]
    }

    private func statement(
        _ kind: ReferenceKind,
        _ number: String,
        name: String? = nil,
        page: Int,
        text: String,
        proof: String = ""
    ) -> ReaderFollowUpStatement {
        ReaderFollowUpStatement(
            reference: DetectedReference(kind: kind, number: number),
            name: name,
            pageIndex: page,
            statementText: text,
            proofText: proof,
            proofPageIndex: proof.isEmpty ? nil : page
        )
    }

    private func anchor(_ id: String, label: String) -> AnswerSourceAnchor {
        AnswerSourceAnchor(
            label: label,
            pageIndex: 0,
            region: NormalizedRect(x: 0, y: 0, width: 0, height: 0),
            sourceID: id
        )
    }

    private func block(
        _ kind: ReferenceKind,
        _ number: String,
        page: Int,
        excerpt: String,
        matched: String,
        origin: ReferenceContentOrigin,
        source: ReferenceEvidenceSource = .pdfText
    ) -> DocumentBlock {
        DocumentBlock(
            reference: DetectedReference(kind: kind, number: number),
            formattedBody: excerpt,
            pageIndex: page,
            evidence: ReferenceEvidence(
                status: .supported,
                sourceExcerpt: excerpt,
                matchedText: matched,
                occurrenceCount: 1,
                startOffset: 0,
                endOffset: matched.utf16.count,
                matchStartOffset: 0,
                matchEndOffset: matched.utf16.count,
                source: source
            ),
            contentOrigin: origin
        )
    }
}

private typealias PageText = ReaderFollowUpCatalog.PageText
