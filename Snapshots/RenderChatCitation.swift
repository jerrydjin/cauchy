import AppKit
import CoreText
import Foundation
import PDFKit
import SwiftMath
import SwiftUI

/// Same flag as `FindBarView`. ImageRenderer drops AppKit-backed math, so the
/// bubble draws SwiftMath into an image when this is set. Defined here because
/// this tool does not compile the find bar.
private struct RendersForSnapshotKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var rendersForSnapshot: Bool {
        get { self[RendersForSnapshotKey.self] }
        set { self[RendersForSnapshotKey.self] = newValue }
    }
}

/// Renders the reader chat citation chrome from a synthetic answer.
/// The before shot reconstructs the broken layout (the link on its own line,
/// the comma stranded, every retrieved page listed). The after shots are the
/// real `MessageBubble`, closed and open. The page shot washes the exact
/// sentence a tag opens.
@main
enum RenderChatCitation {
    @MainActor
    static func main() {
        do {
            try render()
        } catch {
            fputs("snapshot failed: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    @MainActor
    private static func render() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)

        let output = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "Snapshots/out")
        let fixture = CitationFixture()
        try fixture.validate()

        let collapsed = ChatSnapshotChrome(
            caption: "After · collapsed",
            width: 340,
            content: MessageBubble(
                message: fixture.message,
                maxBubbleWidth: 270,
                referenceKeys: fixture.keys
            )
        )
        let expanded = ChatSnapshotChrome(
            caption: "After",
            width: 340,
            content: MessageBubble(
                message: fixture.message,
                maxBubbleWidth: 270,
                referenceKeys: fixture.keys
            )
        )
        let before = ChatSnapshotChrome(
            caption: "Before",
            width: 340,
            content: BrokenCitationBubble(anchors: fixture.anchors)
        )

        try writePNG(before, to: output.appendingPathComponent("chat-citation-before.png"), minimumBytes: 4_000)
        try writePNG(collapsed, to: output.appendingPathComponent("chat-citation-after-collapsed.png"), minimumBytes: 4_000)
        try writePNG(expanded, to: output.appendingPathComponent("chat-citation-after-expanded.png"), minimumBytes: 4_000)

        let passage = try PassageHighlight.render()
        let highlight = ChatSnapshotChrome(
            caption: "After tapping 39",
            width: passage.image.size.width + 40,
            content: Image(nsImage: passage.image)
                .frame(width: passage.image.size.width, height: passage.image.size.height)
        )
        try writePNG(highlight, to: output.appendingPathComponent("chat-citation-highlight.png"), minimumBytes: 4_000)

        let followUps = FollowUpFixture()
        try followUps.validate()
        let withFollowUps = ChatSnapshotChrome(
            caption: "Two follow-ups",
            width: 380,
            content: MessageBubble(
                message: followUps.grounded,
                maxBubbleWidth: 300,
                referenceKeys: followUps.keys,
                followUps: followUps.two,
                followUpsStartVisible: true
            )
        )
        let withoutFollowUps = ChatSnapshotChrome(
            caption: "No follow-up",
            width: 380,
            content: MessageBubble(
                message: followUps.ungrounded,
                maxBubbleWidth: 300,
                followUps: followUps.none,
                followUpsStartVisible: true
            )
        )
        try writePNG(withFollowUps, to: output.appendingPathComponent("chat-follow-ups-two.png"), minimumBytes: 4_000)
        try writePNG(withoutFollowUps, to: output.appendingPathComponent("chat-follow-ups-none.png"), minimumBytes: 4_000)

        fputs(
            "highlight \(Int(passage.bounds.width))x\(Int(passage.bounds.height)) at \(Int(passage.bounds.minX)),\(Int(passage.bounds.minY)) string=\(passage.string)\n",
            stdout
        )

        let pinned = PinnedPassage(
            pageIndex: 38,
            excerpt: "By taking complements, one can show the following inclusion for the closure.",
            fingerprint: "snapshot",
            bounds: NormalizedRect(x: 0.08, y: 0.42, width: 0.84, height: 0.08)
        )
        let withChip = ChatSnapshotChrome(
            caption: "Composer · passage pinned",
            width: 360,
            content: VStack(alignment: .leading, spacing: ConversationChrome.passageChipComposerSpacing) {
                PassageChipView(passage: pinned, role: .composer, onOpen: {}, onDismiss: {})
                SnapshotComposerBar()
            }
        )
        let hoveredPassage = PinnedPassage(
            pageIndex: 36,
            excerpt: "If X is a set with the discrete metric, every set is open. The rest of this synthetic passage is only on the hover card, past the two lines the chip keeps.",
            fingerprint: "snapshot-hover",
            bounds: NormalizedRect(x: 0.08, y: 0.42, width: 0.84, height: 0.08)
        )
        let chipHover = ChatSnapshotChrome(
            caption: "Composer · passage hover",
            width: 400,
            content: VStack(alignment: .leading, spacing: ConversationChrome.passageChipComposerSpacing) {
                PassageChipView(
                    passage: hoveredPassage,
                    role: .composer,
                    showsHoverCard: true,
                    onOpen: {},
                    onDismiss: {}
                )
                SnapshotComposerBar()
            }
        )
        let dismissed = ChatSnapshotChrome(
            caption: "Composer · passage dismissed",
            width: 360,
            content: SnapshotComposerBar()
        )
        let asked = ThreadMessage(
            role: .user,
            content: "What does taking complements show?",
            passage: MessagePassage(pageIndex: pinned.pageIndex, excerpt: pinned.excerpt)
        )
        let sentChip = ChatSnapshotChrome(
            caption: "Sent · passage chip",
            width: 360,
            content: MessageBubble(
                message: asked,
                maxBubbleWidth: 280
            )
        )
        let earlier = ThreadMessage(
            role: .assistant,
            content: "The earlier answer already settled the interval."
        )
        let latestOnly = ChatSnapshotChrome(
            caption: "Only the latest answer has follow-ups",
            width: 420,
            content: VStack(alignment: .leading, spacing: 16) {
                MessageBubble(message: earlier, maxBubbleWidth: 300)
                MessageBubble(
                    message: ThreadMessage(role: .user, content: "What does Theorem 5.4 build on?"),
                    maxBubbleWidth: 300
                )
                MessageBubble(
                    message: followUps.grounded,
                    maxBubbleWidth: 300,
                    referenceKeys: followUps.keys,
                    followUps: followUps.two,
                    followUpsStartVisible: true
                )
            }
        )
        try writePNG(expanded, to: output.appendingPathComponent("jerry-148-citation-expanded.png"), minimumBytes: 4_000)
        try writePNG(withChip, to: output.appendingPathComponent("jerry-148-composer-chip.png"), minimumBytes: 2_000)
        try writePNG(withChip, to: output.appendingPathComponent("jerry-149-composer-chip.png"), minimumBytes: 2_000)
        try writePNG(chipHover, to: output.appendingPathComponent("jerry-149-composer-chip-hover.png"), minimumBytes: 2_000)
        try writePNG(dismissed, to: output.appendingPathComponent("jerry-148-composer-dismissed.png"), minimumBytes: 2_000)
        try writePNG(sentChip, to: output.appendingPathComponent("jerry-148-sent-chip-collapsed.png"), minimumBytes: 2_000)
        try writePNG(sentChip, to: output.appendingPathComponent("jerry-149-sent-chip.png"), minimumBytes: 2_000)
        try writePNG(latestOnly, to: output.appendingPathComponent("jerry-149-follow-ups-latest.png"), minimumBytes: 4_000)
        // The sent chip no longer expands. Keep the old filename pointed at the quote.
        try writePNG(sentChip, to: output.appendingPathComponent("jerry-148-sent-chip-expanded.png"), minimumBytes: 2_000)
    }
}

/// ImageRenderer drops the live glass composer. This bar uses the same
/// padding, corner radius, and placeholder so the chip can be judged
/// against the control it sits on.
private struct SnapshotComposerBar: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ask a question…")
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Auto")
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 7, weight: .semibold))
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: ConversationChrome.composerCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ConversationChrome.composerCornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct CitationFixture {
    let answer = """
    A set is closed exactly when its complement is open. [R2]
    By Proposition 5.3.1, $f$ is continuous exactly when the preimage of a closed set is closed. [R1]
    """

    let keys: Set<ReferenceKey> = [
        ReferenceKey(kind: .proposition, number: "5.3.1"),
    ]

    let anchors: [AnswerSourceAnchor] = [
        AnswerSourceAnchor(
            label: "Proposition 5.3.1",
            pageIndex: 38,
            region: NormalizedRect(x: 0.08, y: 0.42, width: 0.84, height: 0.08),
            sourceID: "R1"
        ),
        AnswerSourceAnchor(
            label: "Proposition 5.3.1 again",
            pageIndex: 38,
            region: NormalizedRect(x: 0.08, y: 0.42, width: 0.84, height: 0.08),
            sourceID: "R1"
        ),
        AnswerSourceAnchor(
            label: "Open and closed sets",
            pageIndex: 36,
            region: NormalizedRect(x: 0.08, y: 0.62, width: 0.8, height: 0.06),
            sourceID: "R2"
        ),
        AnswerSourceAnchor(
            label: "Compactness implies sequential compactness",
            pageIndex: 65,
            region: NormalizedRect(x: 0.1, y: 0.2, width: 0.7, height: 0.05),
            sourceID: "P3"
        ),
        AnswerSourceAnchor(
            label: "Continuous partial derivatives",
            pageIndex: 5,
            region: NormalizedRect(x: 0.1, y: 0.3, width: 0.7, height: 0.05),
            sourceID: "P4"
        ),
    ]

    var message: ThreadMessage {
        ThreadMessage(
            role: .assistant,
            content: answer,
            answerEvidence: AnswerEvidence(
                basis: .pdf,
                sourcePages: [6, 37, 39, 66],
                referencedStatementCount: 2,
                retrievedPassageCount: 4,
                providerID: "snapshot",
                sourceAnchors: anchors,
                citationStatus: .idsResolve,
                citedSourceIDs: ["R1", "R2"]
            )
        )
    }

    func validate() throws {
        let pages = CitedSourceSummary.pages(in: answer, anchors: anchors)
        guard pages.map(\.pageLabel) == ["37", "39"] else {
            throw SnapshotError("cited pages drifted: \(pages.map(\.pageLabel))")
        }
        guard pages.allSatisfy({ !$0.anchor.label.localizedCaseInsensitiveContains("compact") }) else {
            throw SnapshotError("uncited compactness page leaked into sources")
        }
        guard case .highlighted = AnswerSourceNavigation.resolve(pages[1].anchor, pageCount: 80) else {
            throw SnapshotError("page 39 does not open a located passage")
        }
        let lines = AnswerCitationLayout.claimLines(in: answer, anchors: anchors)
        guard lines.count == 2,
              lines[0].chips.map(\.pageLabel) == ["37"],
              lines[1].chips.map(\.pageLabel) == ["39"],
              !lines[1].text.contains("[") else {
            throw SnapshotError("page tags are not at the ends of their claims")
        }
    }
}

/// The layout the branch shipped: one unbreakable underlined link, the comma
/// on the next line, and a sources list of every retrieved page.
private struct BrokenCitationBubble: View {
    var anchors: [AnswerSourceAnchor]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("A set is closed exactly when its complement is open.")
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            brightPill("p. 37")
            Text("By")
                .font(.body)
                .foregroundStyle(.primary)
            Text("Proposition 5.3.1")
                .font(.body)
                .foregroundStyle(Color.accentColor)
                .underline()
            Text(", f is continuous exactly when the preimage of a closed set is closed.")
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            brightPill("p. 39")

            Text("Sources")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(anchors.enumerated()), id: \.offset) { _, anchor in
                    Text("\(anchor.label) (p. \(anchor.pageIndex + 1))")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .underline()
                }
            }
        }
        .padding(.horizontal, ConversationChrome.bubbleContentPaddingH)
        .padding(.vertical, ConversationChrome.bubbleContentPaddingV)
        .frame(maxWidth: 270, alignment: .leading)
        .background(ContentSurface.bubble, in: RoundedRectangle(cornerRadius: ConversationChrome.bubbleCornerRadius))
    }

    private func brightPill(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color.accentColor.opacity(0.18), in: Capsule())
    }
}

private struct ChatSnapshotChrome<Content: View>: View {
    var caption: String
    var width: CGFloat
    var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(width: width, alignment: .leading)
        .background(Color(red: 0.09, green: 0.09, blue: 0.1))
        .environment(\.rendersForSnapshot, true)
        .environment(\.colorScheme, .dark)
    }
}

private enum PassageHighlight {
    struct Rendered {
        var image: NSImage
        var bounds: CGRect
        var string: String
    }

    @MainActor
    static func render() throws -> Rendered {
        let pageSize = CGSize(width: 640, height: 220)
        let body = "Proposition 5.3.1. Let f be a map of spaces.\nThen f is continuous exactly when the preimage of a closed set is closed."
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 6
        let text = NSAttributedString(string: body, attributes: [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph,
        ])
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw SnapshotError("could not open a PDF context")
        }
        context.beginPDFPage(nil)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(mediaBox)
        // PDF space already grows upward, which is the space Core Text draws
        // in. A flip here stores the sentence upside down.
        let inset = CGRect(x: 36, y: 70, width: pageSize.width - 72, height: 110)
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let path = CGPath(rect: inset, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, text.length), path, nil)
        CTFrameDraw(frame, context)
        context.endPDFPage()
        context.closePDF()

        guard let document = PDFDocument(data: data as Data), let page = document.page(at: 0) else {
            throw SnapshotError("synthetic page produced no PDF")
        }
        let needle = "f is continuous exactly when the preimage of a closed set is closed"
        guard let selection = document.findString(needle, withOptions: [.caseInsensitive]).first else {
            let extracted = page.string ?? ""
            throw SnapshotError("exact passage was not in the page text: \(extracted)")
        }
        let media = page.bounds(for: .mediaBox)
        let bounds = selection.bounds(for: page)
        let quoted = selection.string ?? ""
        guard quoted.localizedCaseInsensitiveContains("preimage of a closed set") else {
            throw SnapshotError("selection is not the cited sentence: \(quoted)")
        }
        guard bounds.width > 40, bounds.height > 8, bounds.height < media.height * 0.45,
              media.intersects(bounds) else {
            throw SnapshotError("passage bounds \(bounds) are not a sentence on \(media)")
        }

        let image = NSImage(size: media.size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            NSColor.white.setFill()
            media.fill()
            context.saveGState()
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()
            let wash = bounds.insetBy(dx: -2, dy: -1)
            NSColor.controlAccentColor.withAlphaComponent(CitationChrome.washOpacity).setFill()
            NSBezierPath(roundedRect: wash, xRadius: 2, yRadius: 2).fill()
            return true
        }
        guard let tiff = image.tiffRepresentation, tiff.count > 1000 else {
            throw SnapshotError("page image is empty")
        }
        return Rendered(image: image, bounds: bounds, string: quoted)
    }
}

/// Synthetic notes. The two follow-ups are whatever the planner emits for
/// this answer, so the picture cannot drift from the questions a reader sees.
private struct FollowUpFixture {
    let answer = "A continuous image of a closed interval is connected. [R1]"

    let keys: Set<ReferenceKey> = []

    let statements: [ReaderFollowUpStatement] = [
        ReaderFollowUpStatement(
            reference: DetectedReference(kind: .definition, number: "1.4"),
            name: "Compactness",
            pageIndex: 12,
            statementText: "A set is compact when every open cover has a finite subcover."
        ),
        ReaderFollowUpStatement(
            reference: DetectedReference(kind: .proposition, number: "5.3"),
            pageIndex: 40,
            statementText: "A continuous image of a closed interval is connected.",
            proofText: "The argument uses compactness of the domain to take a finite subcover.",
            proofPageIndex: 40
        ),
        ReaderFollowUpStatement(
            reference: DetectedReference(kind: .theorem, number: "5.4"),
            pageIndex: 46,
            statementText: "The components of a locally connected space are open."
        ),
    ]

    var two: [SuggestedFollowUp] {
        ReaderFollowUps.suggest(
            answer: answer,
            anchors: [
                AnswerSourceAnchor(
                    label: "Proposition 5.3",
                    pageIndex: 40,
                    region: NormalizedRect(x: 0.08, y: 0.42, width: 0.84, height: 0.08),
                    sourceID: "R1"
                ),
            ],
            statements: statements
        )
    }

    var none: [SuggestedFollowUp] {
        ReaderFollowUps.suggest(
            answer: "The selected sentence does not name a result.",
            anchors: [
                AnswerSourceAnchor(
                    label: "Retrieved passage",
                    pageIndex: 4,
                    region: NormalizedRect(x: 0, y: 0, width: 0, height: 0),
                    sourceID: "P1"
                ),
            ],
            statements: statements
        )
    }

    var grounded: ThreadMessage {
        ThreadMessage(
            role: .assistant,
            content: answer,
            answerEvidence: AnswerEvidence(
                basis: .pdf,
                sourcePages: [41],
                referencedStatementCount: 1,
                retrievedPassageCount: 0,
                providerID: "snapshot",
                sourceAnchors: [
                    AnswerSourceAnchor(
                        label: "Proposition 5.3",
                        pageIndex: 40,
                        region: NormalizedRect(x: 0.08, y: 0.42, width: 0.84, height: 0.08),
                        sourceID: "R1"
                    ),
                ],
                citationStatus: .idsResolve,
                citedSourceIDs: ["R1"]
            )
        )
    }

    var ungrounded: ThreadMessage {
        ThreadMessage(
            role: .assistant,
            content: "The selected sentence does not name a result.",
            answerEvidence: AnswerEvidence(
                basis: .insufficient,
                sourcePages: [],
                referencedStatementCount: 0,
                retrievedPassageCount: 0,
                providerID: "snapshot",
                citationStatus: .noResolvableCitation
            )
        )
    }

    func validate() throws {
        let followUps = two
        guard followUps.count == 2,
              followUps[0].question == "Why does the proof of Proposition 5.3 need compactness?",
              followUps[0].pageLabel == "41",
              followUps[1].question == "What does Theorem 5.4 build on?",
              followUps[1].pageLabel == "47" else {
            throw SnapshotError("follow-ups drifted: \(followUps.map { "\($0.question) \($0.pageLabel ?? "-")" })")
        }
        guard none.isEmpty else {
            throw SnapshotError("an ungrounded answer grew a follow-up")
        }
        guard followUps.allSatisfy({ !ReaderFollowUps.isGeneric($0.question) }) else {
            throw SnapshotError("a follow-up is generic")
        }
    }
}

private struct SnapshotError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

@MainActor
private func writePNG<V: View>(_ view: V, to url: URL, minimumBytes: Int) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    renderer.isOpaque = true
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        throw SnapshotError("ImageRenderer produced no PNG")
    }
    guard png.count >= minimumBytes, rep.pixelsWide > 80, rep.pixelsHigh > 80 else {
        throw SnapshotError("PNG is \(png.count) bytes, \(rep.pixelsWide)x\(rep.pixelsHigh)")
    }
    try png.write(to: url)
    fputs("wrote \(url.path) (\(png.count) bytes, \(rep.pixelsWide)x\(rep.pixelsHigh))\n", stdout)
}
