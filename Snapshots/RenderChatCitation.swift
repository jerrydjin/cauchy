import AppKit
import CoreText
import Foundation
import PDFKit
import QuartzCore
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
                    message: ThreadMessage(role: .user, content: "Does a continuous image stay connected?"),
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
        let filtered = ChatSnapshotChrome(
            caption: "The question just asked is not offered again",
            width: 420,
            content: VStack(alignment: .leading, spacing: 16) {
                MessageBubble(
                    message: ThreadMessage(role: .user, content: "What does Theorem 5.4 build on?"),
                    maxBubbleWidth: 300
                )
                MessageBubble(
                    message: followUps.grounded,
                    maxBubbleWidth: 300,
                    referenceKeys: followUps.keys,
                    followUps: followUps.withoutTheQuestionJustAsked,
                    followUpsStartVisible: true
                )
            }
        )
        try writePNG(expanded, to: output.appendingPathComponent("jerry-148-citation-expanded.png"), minimumBytes: 4_000)
        try writePNG(withChip, to: output.appendingPathComponent("jerry-148-composer-chip.png"), minimumBytes: 2_000)
        try writePNG(withChip, to: output.appendingPathComponent("jerry-149-composer-chip.png"), minimumBytes: 2_000)
        try writePNG(withChip, to: output.appendingPathComponent("jerry-151-composer-chip-after.png"), minimumBytes: 2_000)
        try writePNG(chipHover, to: output.appendingPathComponent("jerry-149-composer-chip-hover.png"), minimumBytes: 2_000)
        try writePNG(chipHover, to: output.appendingPathComponent("jerry-151-composer-chip-hover-after.png"), minimumBytes: 2_000)
        try writePNG(dismissed, to: output.appendingPathComponent("jerry-148-composer-dismissed.png"), minimumBytes: 2_000)
        try writePNG(sentChip, to: output.appendingPathComponent("jerry-148-sent-chip-collapsed.png"), minimumBytes: 2_000)
        try writePNG(sentChip, to: output.appendingPathComponent("jerry-149-sent-chip.png"), minimumBytes: 2_000)
        try writePNG(latestOnly, to: output.appendingPathComponent("jerry-149-follow-ups-latest.png"), minimumBytes: 4_000)
        try writePNG(filtered, to: output.appendingPathComponent("jerry-151-follow-ups-filtered.png"), minimumBytes: 4_000)
        // The sent chip no longer expands. Keep the old filename pointed at the quote.
        try writePNG(sentChip, to: output.appendingPathComponent("jerry-148-sent-chip-expanded.png"), minimumBytes: 2_000)

        let chainRule = PinnedPassage(
            pageIndex: 10,
            excerpt: "Theorem 1.5.3 (Chain Rule). Let f : Rn → Rm, g : Rm → Rp and a ∈ Rn. Assume that f is differentiable at a and g is continuous.",
            fingerprint: "snapshot-empty",
            bounds: NormalizedRect(x: 0.08, y: 0.42, width: 0.84, height: 0.08)
        )
        let emptyChat = EmptyPinnedChat(passage: chainRule)
        let emptyURL = output.appendingPathComponent("jerry-151-empty-chat.png")
        try writePNG(emptyChat, to: emptyURL, minimumBytes: 4_000)
        try assertChipHugsItsText(in: emptyURL, panelHeight: EmptyPinnedChat.panelHeight)

        let tallHover = TallHoverChip(passage: hoveredPassage)
        let tallHoverURL = output.appendingPathComponent("jerry-151-chip-hover-tall.png")
        try writePNG(tallHover, to: tallHoverURL, minimumBytes: 4_000)
        try assertChipHugsItsText(in: tallHoverURL, panelHeight: TallHoverChip.panelHeight, allowsCardBar: true)

        try assertLabelledReferenceIsOneLink()
        let linkRest = RefLinkSentence(showsHover: false)
        try writePNG(linkRest, to: output.appendingPathComponent("jerry-151-ref-link-rest.png"), minimumBytes: 1_000)
        let linkHover = RefLinkSentence(showsHover: true)
        try writePNG(linkHover, to: output.appendingPathComponent("jerry-151-ref-link-hover.png"), minimumBytes: 1_000)

        let chipNoBar = QuoteCardShot(card: false)
        let chipNoBarURL = output.appendingPathComponent("jerry-151-chip-nobar.png")
        try writePNG(chipNoBar, to: chipNoBarURL, minimumBytes: 1_000)
        try assertQuoteTextStartsAtThePadding(in: chipNoBarURL)

        let hoverNoBar = QuoteCardShot(card: true)
        let hoverNoBarURL = output.appendingPathComponent("jerry-151-hovercard-nobar.png")
        try writePNG(hoverNoBar, to: hoverNoBarURL, minimumBytes: 1_000)
        try assertQuoteTextStartsAtThePadding(in: hoverNoBarURL)

        try assertProbeStaysOutOfTheChat()
        let firstOpen = FirstOpenCheckingChat()
        try writePNG(firstOpen, to: output.appendingPathComponent("jerry-151-first-open-checking.png"), minimumBytes: 2_000)

        let headerEmpty = HeaderBand(scrolled: false)
        try writePNG(headerEmpty, to: output.appendingPathComponent("jerry-151-header-empty.png"), minimumBytes: 2_000)
        let headerScrolled = HeaderBand(scrolled: true)
        let headerScrolledURL = output.appendingPathComponent("jerry-151-header-scrolled.png")
        try writePNG(headerScrolled, to: headerScrolledURL, minimumBytes: 4_000)
        try assertHeaderHidesTheLineUnderneath()
        try renderHeaderScrolledUnder(to: output.appendingPathComponent("jerry-151-header-scrolled-under.png"))

        try renderJerry152(to: output)
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

/// A tall empty conversation. The chip is offered the spare height, the same
/// proposal the safe-area bar makes, and has to stay two lines at the bottom.
private struct EmptyPinnedChat: View {
    static let panelWidth: CGFloat = 390
    static let panelHeight: CGFloat = 720

    var passage: PinnedPassage

    var body: some View {
        ZStack {
            ConversationChrome.headerBackdrop
            VStack(spacing: 0) {
                snapshotHeader
                Text("Ask a question about this passage")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                Spacer(minLength: 0)
            }
            .frame(width: Self.panelWidth, height: Self.panelHeight, alignment: .top)
            TallChipSlot {
                PassageChipView(passage: passage, role: .composer, onOpen: {}, onDismiss: {})
            }
            .frame(width: Self.panelWidth, height: Self.panelHeight, alignment: .bottom)
        }
        .frame(width: Self.panelWidth, height: Self.panelHeight)
        .environment(\.colorScheme, .dark)
    }
}

/// Offers the chip the panel's spare height, then pins whatever height it
/// actually takes to the bottom, 8pt above the composer.
private struct TallChipSlot<Chip: View>: View {
    @ViewBuilder var chip: Chip

    var body: some View {
        VStack(alignment: .leading, spacing: ConversationChrome.passageChipComposerSpacing) {
            chip
            SnapshotComposerBar()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}

/// Hover, offered the same tall height. The card and the chip both hug.
private struct TallHoverChip: View {
    static let panelWidth: CGFloat = 390
    static let panelHeight: CGFloat = 720

    var passage: PinnedPassage

    var body: some View {
        ZStack {
            ConversationChrome.headerBackdrop
            snapshotHeader
                .frame(width: Self.panelWidth, height: Self.panelHeight, alignment: .top)
            TallChipSlot {
                PassageChipView(
                    passage: passage,
                    role: .composer,
                    showsHoverCard: true,
                    onOpen: {},
                    onDismiss: {}
                )
            }
            .frame(width: Self.panelWidth, height: Self.panelHeight, alignment: .bottom)
        }
        .frame(width: Self.panelWidth, height: Self.panelHeight)
        .environment(\.colorScheme, .dark)
    }
}

private struct HeaderBand: View {
    var scrolled: Bool

    var body: some View {
        ZStack(alignment: .top) {
            ConversationChrome.headerBackdrop
            if scrolled {
                VStack(alignment: .leading, spacing: 14) {
                    Text("What does the definition of norms require?")
                        .font(.body)
                        .foregroundStyle(.primary)
                        .padding(.top, 30)
                    Text("A norm on a finite-dimensional space is a continuous function, and every linear map is bounded.")
                        .font(.body)
                        .foregroundStyle(.primary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ContentSurface.bubble, in: RoundedRectangle(cornerRadius: 18))
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                Text("Ask a question about this passage")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 78)
            }
            snapshotHeader
        }
        .frame(width: 390, height: scrolled ? 280 : 150)
        .environment(\.colorScheme, .dark)
    }
}

private var snapshotHeader: some View {
    ConversationThreadHeader(
        title: "Derivative Order and Matrix Transfor…",
        pageNumber: 11
    ) {
        Image(systemName: "chevron.left")
            .font(.body.weight(.semibold))
            .frame(width: 28, height: 28)
    } trailing: {
        Image(systemName: "ellipsis")
            .font(.body.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 22)
    }
}

/// The chip hugs its text and sits down by the composer. A card that takes
/// the panel's spare height fails here. The blue quote bar is gone.
@MainActor
private func assertChipHugsItsText(in url: URL, panelHeight: CGFloat, allowsCardBar: Bool = false) throws {
    let bitmap = try Bitmap(url)
    let runs = bitmap.quoteBarRuns()
    guard runs.isEmpty else {
        throw SnapshotError("quote bar is back in \(url.lastPathComponent)")
    }
    let titleY = bitmap.averageRow { $0.r > 210 && $0.g > 210 && $0.b > 210 }
    guard let titleY else {
        throw SnapshotError("could not find the header title in \(url.lastPathComponent)")
    }
    guard let range = bitmap.contentYRange() else {
        throw SnapshotError("empty panel in \(url.lastPathComponent)")
    }
    // Row numbers grow either up or down depending on the bitmap, so the pin
    // is the content farthest from the title, not the larger row number.
    let gap = max(abs(range.lowerBound - titleY), abs(range.upperBound - titleY))
    guard gap > bitmap.height / 3 else {
        throw SnapshotError("chip content spans \(range) and is \(gap)px from the title in \(url.lastPathComponent); it is not pinned above the composer")
    }
    try assertChipHugsWhenOfferedSpareHeight(showsHoverCard: allowsCardBar)
    fputs("chip hugs content in \(url.lastPathComponent) (panel \(Int(panelHeight))pt)\n", stdout)
}

/// Offers the chip the panel's spare height. The card must stay at the top
/// of that offer instead of painting the whole frame.
@MainActor
private func assertChipHugsWhenOfferedSpareHeight(showsHoverCard: Bool) throws {
    let passage = PinnedPassage(
        pageIndex: 10,
        excerpt: "Theorem 1.5.3 (Chain Rule). Let f : Rn → Rm, g : Rm → Rp and a ∈ Rn. Assume that f is differentiable at a and g is continuous.",
        fingerprint: "hug-probe",
        bounds: NormalizedRect(x: 0.08, y: 0.42, width: 0.84, height: 0.08)
    )
    let probe = HugProbe(passage: passage, showsHoverCard: showsHoverCard)
        .environment(\.colorScheme, .dark)
    let renderer = ImageRenderer(content: probe)
    renderer.scale = 2
    renderer.isOpaque = true
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
        throw SnapshotError("chip hug probe produced no image")
    }
    let bitmap = try Bitmap(rep)
    guard let range = bitmap.contentYRange(slack: 10) else {
        throw SnapshotError("chip hug probe drew nothing")
    }
    let points = CGFloat(range.upperBound - range.lowerBound) / 2
    let limit: CGFloat = showsHoverCard ? 280 : 120
    guard points < limit else {
        throw SnapshotError("chip is \(Int(points))pt tall when offered 600pt")
    }
    fputs("chip hug probe is \(Int(points))pt (hover \(showsHoverCard))\n", stdout)
}

private struct HugProbe: View {
    var passage: PinnedPassage
    var showsHoverCard: Bool

    var body: some View {
        PassageChipView(
            passage: passage,
            role: .composer,
            showsHoverCard: showsHoverCard,
            onOpen: {},
            onDismiss: {}
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .frame(width: 358, height: 600)
        .background(Color(white: 0.15))
    }
}

private struct RefLinkSentence: View {
    var showsHover: Bool

    var body: some View {
        ReferenceLinkedText(
            text: "By Proposition 5.3.1, f is continuous exactly when the preimage is open.",
            knownKeys: [ReferenceKey(kind: .proposition, number: "5.3.1")],
            linkShowsHover: showsHover
        )
        .font(.body)
        .padding(28)
        .frame(width: 560, alignment: .leading)
        .background(Color(white: 0.12))
        .environment(\.colorScheme, .dark)
    }
}

private struct QuoteCardShot: View {
    var card: Bool

    private var excerpt: String {
        "Theorem 1.5.3 (Chain Rule). Let f : Rn → Rm and g : Rm → Rp. Assume that f is differentiable at a and g is continuous. The rest of this sentence is only on the hover card."
    }

    var body: some View {
        let passage = PinnedPassage(
            pageIndex: 10,
            excerpt: excerpt,
            fingerprint: "nobar",
            bounds: NormalizedRect(x: 0.08, y: 0.42, width: 0.84, height: 0.08)
        )
        Group {
            if card {
                PassageQuoteCard(text: excerpt)
            } else {
                PassageChipView(passage: passage, role: .composer, onOpen: {}, onDismiss: {})
            }
        }
        .padding(32)
        .frame(width: 420, alignment: .topLeading)
        .background(Color(white: 0.15))
        .environment(\.colorScheme, .dark)
    }
}

private struct FirstOpenCheckingChat: View {
    var body: some View {
        ZStack {
            ConversationChrome.headerBackdrop
            VStack(spacing: 0) {
                snapshotHeader
                Text("Ask a question about this passage")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
                Spacer(minLength: 0)
                SnapshotComposerBar()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .frame(width: 390, height: 520)
        .environment(\.colorScheme, .dark)
    }
}

private func assertLabelledReferenceIsOneLink() throws {
    let text = "By Proposition 5.3.1, f is continuous exactly when the preimage is open."
    let match = DetectedReferenceMatch(
        reference: DetectedReference(kind: .proposition, number: "5.3.1"),
        range: text.range(of: "Proposition 5.3.1")!
    )
    let pieces = InlineReferenceFlow.pieces(in: text, matches: [match])
    let links = pieces.compactMap { piece -> (String, String)? in
        if case .link(let label, let suffix, _) = piece { return (label, suffix) }
        return nil
    }
    guard links.count == 1 else {
        throw SnapshotError("labelled reference split into \(links.count) links")
    }
    guard links[0].0 == "Proposition\u{00A0}5.3.1", !links[0].0.contains(" "), links[0].1 == ", " else {
        throw SnapshotError("citation is \(links[0].0) suffix \(links[0].1)")
    }
    let samples = ["Theorem 1.5.3", "Lemma 2", "Definition 4.1", "Corollary 3.2.1", "Equation 1.2", "Section 5"]
    for sample in samples {
        let line = "See \(sample), next."
        let sampleMatch = DetectedReferenceMatch(
            reference: DetectedReference(kind: .theorem, number: "1"),
            range: line.range(of: sample)!
        )
        let samplePieces = InlineReferenceFlow.pieces(in: line, matches: [sampleMatch])
        let sampleLinks = samplePieces.compactMap { piece -> String? in
            if case .link(let label, _, _) = piece { return label }
            return nil
        }
        guard sampleLinks == [sample.replacingOccurrences(of: " ", with: "\u{00A0}")] else {
            throw SnapshotError("\(sample) split into \(sampleLinks)")
        }
    }
}

private func assertProbeStaysOutOfTheChat() throws {
    let connector = AssistantConnectorID.antigravity.connector
    let ready = AskPresentation.make(connector: connector, state: .ready)
    let states: [ReadinessState] = [.unknown, .checking, .blocked(.notSignedIn(.antigravity))]
    for state in states {
        let ask = AskPresentation.make(connector: connector, state: state)
        guard ask == ready, ask.canAsk, ask.message == nil, ask.buttonTitle == nil else {
            throw SnapshotError("a probe state is visible in the chat")
        }
    }
    let signedOut = ConnectorStatus.resolved(
        access: connector.access,
        name: connector.name,
        readiness: .blocked(.notSignedIn(.antigravity))
    )
    guard !signedOut.allowsSelection,
          signedOut.menuTitle(name: connector.name) == "Antigravity — Not signed in" else {
        throw SnapshotError("signed-out Antigravity is not a greyed picker row")
    }
    let missing = ConnectorStatus.resolved(
        access: AssistantConnectorID.codex.connector.access,
        name: "Codex",
        readiness: .blocked(.notInstalled(.codex))
    )
    guard missing.menuTitle(name: "Codex") == "Codex — Not installed", !missing.allowsSelection else {
        throw SnapshotError("missing Codex is not a greyed picker row")
    }
    let checking = ConnectorStatus.resolved(
        access: connector.access,
        name: connector.name,
        readiness: .checking
    )
    guard checking.hint == nil, checking.shortNote == nil, checking.allowsSelection else {
        throw SnapshotError("checking still publishes a status line")
    }
}

/// The quote starts at the card's 12pt padding. The old bar added another
/// 10pt before the text, so an inset near 20pt means that width is still there.
private func assertQuoteTextStartsAtThePadding(in url: URL) throws {
    let bitmap = try Bitmap(url)
    guard bitmap.quoteBarRuns().isEmpty else {
        throw SnapshotError("quote bar is back in \(url.lastPathComponent)")
    }
    guard let inset = bitmap.quoteTextInset() else {
        throw SnapshotError("could not measure the quote inset in \(url.lastPathComponent)")
    }
    let points = CGFloat(inset) / 2
    guard points >= 8, points <= 16 else {
        throw SnapshotError("quote text starts \(String(format: "%.1f", points))pt into the card in \(url.lastPathComponent); the padding is 12pt")
    }
    fputs("quote text inset \(String(format: "%.1f", points))pt in \(url.lastPathComponent)\n", stdout)
}

/// A bright line placed on the subtitle must not survive the header.
@MainActor
private func assertHeaderHidesTheLineUnderneath() throws {
    let probe = HeaderLeakProbe()
    let renderer = ImageRenderer(content: probe.environment(\.displayScale, 2).environment(\.colorScheme, .dark))
    renderer.scale = 2
    renderer.isOpaque = true
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
        throw SnapshotError("header probe produced no image")
    }
    let bitmap = try Bitmap(rep)
    var leaked = 0
    var titleInk = 0
    for y in 0..<bitmap.height {
        for x in 0..<bitmap.width {
            let p = bitmap.pixel(x, y)
            if p.r > 220 && p.g < 40 && p.b < 40 { leaked += 1 }
            if p.r > 180 && p.g > 180 && p.b > 180 { titleInk += 1 }
        }
    }
    guard leaked == 0 else {
        throw SnapshotError("header lets \(leaked) pixels of the line underneath show through the subtitle")
    }
    guard titleInk > 40 else {
        throw SnapshotError("header subtitle did not draw")
    }
    fputs("header hides the line underneath (\(titleInk) title pixels)\n", stdout)
}

/// Red sits on the subtitle. The rest of the probe is the panel colour, so a
/// red pixel anywhere means the header band is still clear.
private struct HeaderLeakProbe: View {
    var body: some View {
        ZStack(alignment: .top) {
            ConversationChrome.headerBackdrop
            Color.red
                .frame(height: 18)
                .padding(.top, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            snapshotHeader
        }
        .frame(width: 390, height: 120)
        .environment(\.colorScheme, .dark)
    }
}

/// The marked line of a long answer is scrolled into the header's rectangle.
/// ImageRenderer does not draw a ScrollView, so the harness hosts one in a
/// window and drives ScrollViewReader before taking the bitmap.
@MainActor
private final class HeaderScrollProbe: ObservableObject {
    @Published var generation = 0
    var anchorMinY: CGFloat = -10_000
}

private struct AnchorMinYKey: PreferenceKey {
    static var defaultValue: CGFloat = -10_000
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if value < -9_000 { value = next }
        else if next > -9_000 { value = next }
    }
}

private struct HeaderScrolledUnder: View {
    static let panelWidth: CGFloat = 390
    static let panelHeight: CGFloat = 640

    @ObservedObject var probe: HeaderScrollProbe

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    MessageBubble(
                        message: ThreadMessage(
                            role: .user,
                            content: "What does the definition of norms require?"
                        ),
                        maxBubbleWidth: 320
                    )
                    answer
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                proxy.scrollTo("under-header", anchor: .top)
            }
            .onChange(of: probe.generation) { _, _ in
                proxy.scrollTo("under-header", anchor: .top)
            }
        }
        .coordinateSpace(name: "panel")
        .frame(width: Self.panelWidth, height: Self.panelHeight)
        .background(ConversationChrome.headerBackdrop)
        .environment(\.colorScheme, .dark)
        .onPreferenceChange(AnchorMinYKey.self) { probe.anchorMinY = $0 }
    }

    private var answer: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(Self.lead)
                Text(Self.under)
                    .id("under-header")
                    .background {
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: AnchorMinYKey.self,
                                value: geo.frame(in: .named("panel")).minY
                            )
                        }
                    }
                ForEach(0..<8, id: \.self) { index in
                    Text(Self.tail + "\n\nPassage \(index + 1) stays below the header, so the marked line can rest at the top of the panel.")
                }
            }
            .font(.body)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, ConversationChrome.answerPaddingH)
            .padding(.vertical, ConversationChrome.answerPaddingV)
            .frame(maxWidth: 340, alignment: .leading)
            .background(
                ContentSurface.bubble,
                in: RoundedRectangle(cornerRadius: ConversationChrome.bubbleCornerRadius)
            )
            Spacer(minLength: ConversationChrome.bubbleHorizontalInset)
        }
    }

    /// Paragraphs above the marked line. Scrolling that line to the top
    /// carries these under the header and then off the panel.
    static let lead = """
    A norm on a finite-dimensional space is a continuous function, and every linear map between those spaces is bounded. The operator norm is the smallest constant that works for every vector, and it is attained on the unit sphere.

    Equivalence of norms follows from compactness of that sphere. Once two norms are equivalent, completeness and the open sets transfer from one to the other without a further argument. These opening paragraphs sit above the header once the thread is scrolled partway through the answer.
    """

    /// The line ScrollViewReader parks at the top of the panel, which is the header's rectangle.
    static let under = """
    This sentence is scrolled underneath the page subtitle, so its glyphs sit in the header's rectangle rather than starting below it. The same sentence wraps on, and the lines that cross the header's lower edge are the ones still visible.
    """

    static let tail = """
    What remains on screen is the rest of that answer, still inside the same bubble. The header has to cover the lines above this one completely. The title and Page 11 are the only type in that band.

    A further paragraph keeps the scroll view taller than the panel, so the marked line can rest at the top instead of bouncing back down. Finite-dimensional normed spaces are complete, and a linear map out of one is continuous exactly when it is bounded.

    The last paragraph exists so the offset is a real one. The backdrop stays the panel colour, and the scrolled text stays behind it.
    """
}

@MainActor
private func renderHeaderScrolledUnder(to url: URL) throws {
    if !NSApp.isRunning {
        NSApp.finishLaunching()
    }
    let policy = NSApp.activationPolicy()
    NSApp.setActivationPolicy(.accessory)
    defer { NSApp.setActivationPolicy(policy) }
    let probe = HeaderScrollProbe()
    let scrolled = try captureScrolledPanel(HeaderScrolledUnder(probe: probe), probe: probe)
    let factor = scrolled.pixelsWide < Int(HeaderScrolledUnder.panelWidth * 1.5) ? 2 : 1
    let content = try scaleUpright(scrolled, by: factor)
    let header = try renderSnapshotHeader()
    guard let covered = content.copy() as? NSBitmapImageRep else {
        throw SnapshotError("could not copy the scrolled snapshot")
    }
    try paintHeader(header, onto: covered)
    try assertAnswerLiesUnderTheHeader(content: content, header: header, covered: covered)
    let composed = try composeHeaderStrip(
        panel: covered,
        stripPixels: headerPixelsHigh(header, fittedTo: covered.pixelsWide)
    )
    guard let png = composed.representation(using: .png, properties: [:]) else {
        throw SnapshotError("header scroll snapshot produced no PNG")
    }
    guard png.count >= 8_000 else {
        throw SnapshotError("header scroll snapshot is \(png.count) bytes")
    }
    try png.write(to: url)
    fputs("wrote \(url.path) (\(png.count) bytes, \(composed.pixelsWide)x\(composed.pixelsHigh))\n", stdout)
}

@MainActor
private func captureScrolledPanel<V: View>(_ view: V, probe: HeaderScrollProbe) throws -> NSBitmapImageRep {
    let hosted = try HostedPanel(root: view)
    defer { hosted.window.close() }
    pump(0.35)
    if !anchorRestsUnderTheHeader(probe.anchorMinY) {
        probe.generation += 1
        pump(0.35)
    }
    if !anchorRestsUnderTheHeader(probe.anchorMinY), let scroll = hosted.hosting.firstDescendant(of: NSScrollView.self) {
        try nudgeScrollView(scroll, probe: probe)
    }
    guard anchorRestsUnderTheHeader(probe.anchorMinY) else {
        let origin = hosted.hosting.firstDescendant(of: NSScrollView.self)?.contentView.bounds.origin.y ?? -1
        throw SnapshotError("scrolled answer anchor is at \(probe.anchorMinY) (scroll origin \(origin)); it is not under the header")
    }
    guard let rep = cacheBitmap(of: hosted.hosting), bitmapHasInk(rep) else {
        throw SnapshotError("scrolled snapshot cache is blank (\(hosted.hosting.bounds.size))")
    }
    fputs("scrolled header anchor \(probe.anchorMinY) cache \(rep.pixelsWide)x\(rep.pixelsHigh)\n", stdout)
    return rep
}

private func anchorRestsUnderTheHeader(_ y: CGFloat) -> Bool {
    y > -2 && y < 12
}

@MainActor
private func nudgeScrollView(_ scroll: NSScrollView, probe: HeaderScrollProbe) throws {
    let clip = scroll.contentView
    let start = clip.bounds.origin
    let delta = probe.anchorMinY
    clip.scroll(to: NSPoint(x: start.x, y: start.y + delta))
    scroll.reflectScrolledClipView(clip)
    pump(0.25)
    guard !anchorRestsUnderTheHeader(probe.anchorMinY) else { return }
    clip.scroll(to: start)
    scroll.reflectScrolledClipView(clip)
    pump(0.1)
    clip.scroll(to: NSPoint(x: start.x, y: start.y - delta))
    scroll.reflectScrolledClipView(clip)
    pump(0.25)
}

@MainActor
private func renderSnapshotHeader() throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(
        content: snapshotHeader
            .environment(\.colorScheme, .dark)
            .frame(width: HeaderScrolledUnder.panelWidth)
    )
    renderer.scale = 2
    renderer.isOpaque = false
    renderer.proposedSize = ProposedViewSize(width: HeaderScrolledUnder.panelWidth, height: nil)
    guard let image = renderer.nsImage else {
        throw SnapshotError("header image did not render")
    }
    var best = image.representations.compactMap { $0 as? NSBitmapImageRep }.max { $0.pixelsWide < $1.pixelsWide }
    if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), rep.pixelsWide > (best?.pixelsWide ?? 0) {
        best = rep
    }
    guard let rep = best else { throw SnapshotError("header image did not render") }
    fputs("header image \(rep.pixelsWide)x\(rep.pixelsHigh)\n", stdout)
    return rep
}

@MainActor
private func scaleUpright(_ source: NSBitmapImageRep, by factor: Int) throws -> NSBitmapImageRep {
    let width = source.pixelsWide * factor
    let height = source.pixelsHigh * factor
    let pointSize = NSSize(
        width: HeaderScrolledUnder.panelWidth,
        height: HeaderScrolledUnder.panelHeight
    )
    guard let dest = makeBitmap(pixelsWide: width, pixelsHigh: height, pointSize: pointSize) else {
        throw SnapshotError("could not scale the scrolled snapshot")
    }
    for y in 0..<source.pixelsHigh {
        for x in 0..<source.pixelsWide {
            guard let color = source.colorAt(x: x, y: y) else { continue }
            for dy in 0..<factor {
                for dx in 0..<factor {
                    dest.setColor(color, atX: x * factor + dx, y: y * factor + dy)
                }
            }
        }
    }
    return dest
}

private func headerPixelsHigh(_ header: NSBitmapImageRep, fittedTo width: Int) -> Int {
    guard header.pixelsWide > 0 else { return header.pixelsHigh }
    return header.pixelsHigh * width / header.pixelsWide
}

@MainActor
private func paintHeader(_ header: NSBitmapImageRep, onto dest: NSBitmapImageRep) throws {
    let strip = headerPixelsHigh(header, fittedTo: dest.pixelsWide)
    guard strip > 0, strip < dest.pixelsHigh else {
        throw SnapshotError("header strip \(strip)px does not fit the panel")
    }
    for y in 0..<strip {
        let hy = min(header.pixelsHigh - 1, y * header.pixelsHigh / strip)
        for x in 0..<dest.pixelsWide {
            let hx = min(header.pixelsWide - 1, x * header.pixelsWide / dest.pixelsWide)
            guard let color = header.colorAt(x: hx, y: hy) else { continue }
            dest.setColor(color, atX: x, y: y)
        }
    }
}

@MainActor
private struct HostedPanel<Content: View> {
    let window: NSWindow
    let hosting: NSHostingView<Content>

    init(root: Content, size: NSSize? = nil) throws {
        let size = size ?? NSSize(width: HeaderScrolledUnder.panelWidth, height: HeaderScrolledUnder.panelHeight)
        let panel = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.backgroundColor = .windowBackgroundColor
        panel.isOpaque = true
        let hosting = NSHostingView(rootView: root)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.wantsLayer = true
        hosting.layer?.contentsScale = 2
        guard let content = panel.contentView else {
            throw SnapshotError("header snapshot window has no content view")
        }
        content.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: content.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        self.window = panel
        self.hosting = hosting
        panel.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        panel.layoutIfNeeded()
        panel.displayIfNeeded()
    }
}

@MainActor
private func pump(_ seconds: TimeInterval) {
    let until = Date().addingTimeInterval(seconds)
    while Date() < until {
        RunLoop.current.run(mode: .common, before: Date().addingTimeInterval(0.02))
    }
    CATransaction.flush()
}

@MainActor
private func bitmap(of view: NSView, scale: CGFloat) throws -> NSBitmapImageRep {
    view.layoutSubtreeIfNeeded()
    applyContentsScale(scale, to: view)
    view.needsDisplay = true
    view.window?.displayIfNeeded()
    CATransaction.flush()
    guard view.bounds.width > 50, view.bounds.height > 50 else {
        throw SnapshotError("header snapshot view is \(view.bounds.size)")
    }

    if let cached = cacheBitmap(of: view) {
        let ink = bitmapHasInk(cached)
        fputs("cacheDisplay \(cached.pixelsWide)x\(cached.pixelsHigh) ink \(ink)\n", stdout)
        if ink {
            let cachedScale = CGFloat(cached.pixelsWide) / view.bounds.width
            if cachedScale >= scale - 0.1 { return cached }
            return try scaleBitmap(cached, of: view, to: scale)
        }
    }
    if let pdf = pdfBitmap(of: view, scale: scale), bitmapHasInk(pdf) {
        fputs("header snapshot via PDF at \(pdf.pixelsWide)x\(pdf.pixelsHigh)\n", stdout)
        return pdf
    }
    let rendered = try layerBitmap(of: view, scale: scale)
    if bitmapHasInk(rendered) {
        fputs("header snapshot via layer at \(rendered.pixelsWide)x\(rendered.pixelsHigh)\n", stdout)
        return rendered
    }
    throw SnapshotError("header snapshot bitmap is blank (\(view.bounds.size))")
}

@MainActor
private func cacheBitmap(of view: NSView) -> NSBitmapImageRep? {
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep
}

@MainActor
private func pdfBitmap(of view: NSView, scale: CGFloat) -> NSBitmapImageRep? {
    let data = view.dataWithPDF(inside: view.bounds)
    guard data.count > 200,
          let provider = CGDataProvider(data: data as CFData),
          let document = CGPDFDocument(provider),
          let page = document.page(at: 1) else { return nil }
    let width = Int((view.bounds.width * scale).rounded())
    let height = Int((view.bounds.height * scale).rounded())
    guard let rep = makeBitmap(pixelsWide: width, pixelsHigh: height, pointSize: view.bounds.size),
          let context = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else { return nil }
    context.setFillColor(CGColor(gray: 0.2, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.saveGState()
    context.scaleBy(x: scale, y: scale)
    context.drawPDFPage(page)
    context.restoreGState()
    return rep
}

@MainActor
private func layerBitmap(of view: NSView, scale: CGFloat) throws -> NSBitmapImageRep {
    guard let layer = view.layer else { throw SnapshotError("header snapshot view has no layer") }
    let width = Int((view.bounds.width * scale).rounded())
    let height = Int((view.bounds.height * scale).rounded())
    guard let rep = makeBitmap(pixelsWide: width, pixelsHigh: height, pointSize: view.bounds.size),
          let context = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else {
        throw SnapshotError("could not allocate the header snapshot")
    }
    context.saveGState()
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: scale, y: -scale)
    layer.render(in: context)
    context.restoreGState()
    return rep
}

@MainActor
private func scaleBitmap(_ source: NSBitmapImageRep, of view: NSView, to scale: CGFloat) throws -> NSBitmapImageRep {
    let width = Int((view.bounds.width * scale).rounded())
    let height = Int((view.bounds.height * scale).rounded())
    guard let image = source.cgImage,
          let rep = makeBitmap(pixelsWide: width, pixelsHigh: height, pointSize: view.bounds.size),
          let context = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else {
        throw SnapshotError("could not scale the header snapshot")
    }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return rep
}

private func makeBitmap(pixelsWide: Int, pixelsHigh: Int, pointSize: NSSize) -> NSBitmapImageRep? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelsWide,
        pixelsHigh: pixelsHigh,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }
    rep.size = pointSize
    return rep
}

private func bitmapHasInk(_ rep: NSBitmapImageRep) -> Bool {
    guard let origin = rep.colorAt(x: 0, y: 0) else { return false }
    let stepX = max(1, rep.pixelsWide / 48)
    let stepY = max(1, rep.pixelsHigh / 48)
    var ink = 0
    var y = 0
    while y < rep.pixelsHigh {
        var x = 0
        while x < rep.pixelsWide {
            if let color = rep.colorAt(x: x, y: y),
               abs(color.redComponent - origin.redComponent) > 0.08
                || abs(color.greenComponent - origin.greenComponent) > 0.08
                || abs(color.blueComponent - origin.blueComponent) > 0.08 {
                ink += 1
            }
            x += stepX
        }
        y += stepY
    }
    return ink > 8
}

private func applyContentsScale(_ scale: CGFloat, to view: NSView) {
    view.wantsLayer = true
    view.layer?.contentsScale = scale
    for subview in view.subviews {
        applyContentsScale(scale, to: subview)
    }
}

@MainActor
private func assertAnswerLiesUnderTheHeader(
    content: NSBitmapImageRep,
    header: NSBitmapImageRep,
    covered: NSBitmapImageRep
) throws {
    let scale = CGFloat(covered.pixelsWide) / HeaderScrolledUnder.panelWidth
    guard scale >= 1.5 else {
        throw SnapshotError("header snapshot is \(covered.pixelsWide)x\(covered.pixelsHigh), not 2x")
    }
    let strip = headerPixelsHigh(header, fittedTo: covered.pixelsWide)
    guard strip > Int(36 * scale), strip < Int(90 * scale) else {
        throw SnapshotError("header band is \(strip)px")
    }
    guard covered.pixelsWide == content.pixelsWide, covered.pixelsHigh == content.pixelsHigh else {
        throw SnapshotError("header composite changed the panel size")
    }
    let width = min(content.pixelsWide, covered.pixelsWide)
    var titleInk = 0
    var textUnder = 0
    var leaked = 0
    for y in 0..<strip {
        let hy = min(header.pixelsHigh - 1, y * header.pixelsHigh / strip)
        for x in stride(from: 0, to: width, by: 1) {
            let hx = min(header.pixelsWide - 1, x * header.pixelsWide / width)
            let answer = sample(content, x, y)
            let title = sample(header, hx, hy)
            let painted = sample(covered, x, y)
            if title.r > 180, title.g > 180, title.b > 180 { titleInk += 1 }
            if channelGap(answer, title) > 28 {
                textUnder += 1
                if channelGap(painted, title) > 18 { leaked += 1 }
            }
        }
    }
    guard titleInk > 40 else {
        throw SnapshotError("header title did not draw (\(titleInk) bright pixels)")
    }
    guard textUnder > 400 else {
        throw SnapshotError("answer text is not under the header (\(textUnder) pixels); the scroll left it below the band")
    }
    guard leaked == 0 else {
        throw SnapshotError("header lets \(leaked) pixels of the scrolled answer show through")
    }
    var below = 0
    let belowEnd = min(covered.pixelsHigh, strip + Int(36 * scale))
    for y in strip..<belowEnd {
        for x in stride(from: 0, to: width, by: 2) {
            let pixel = sample(covered, x, y)
            if pixel.r > 180, pixel.g > 180, pixel.b > 180 { below += 1 }
        }
    }
    guard below > 80 else {
        throw SnapshotError("the answer does not continue below the header (\(below) bright pixels)")
    }
    fputs("answer sits under the header: \(textUnder) covered pixels, \(below) continue below, strip \(strip)px\n", stdout)
}

private func sample(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
    guard let color = rep.colorAt(x: x, y: y) else { return (0, 0, 0) }
    func byte(_ channel: CGFloat) -> UInt8 {
        UInt8(min(255, max(0, Int((channel * 255).rounded()))))
    }
    return (byte(color.redComponent), byte(color.greenComponent), byte(color.blueComponent))
}

private func brightCount(_ bitmap: Bitmap, rows: Range<Int>) -> Int {
    var count = 0
    for y in rows where y >= 0 && y < bitmap.height {
        for x in stride(from: 0, to: bitmap.width, by: 2) {
            let pixel = bitmap.pixel(x, y)
            if pixel.r > 180, pixel.g > 180, pixel.b > 180 { count += 1 }
        }
    }
    return count
}

private func channelGap(_ a: (r: UInt8, g: UInt8, b: UInt8), _ b: (r: UInt8, g: UInt8, b: UInt8)) -> Int {
    max(abs(Int(a.r) - Int(b.r)), abs(Int(a.g) - Int(b.g)), abs(Int(a.b) - Int(b.b)))
}

/// The panel, then the same header band cropped underneath it. Pixel rows stay
/// top-down, which is the order `colorAt` uses, so the crop cannot flip.
@MainActor
private func composeHeaderStrip(panel: NSBitmapImageRep, stripPixels: Int) throws -> NSBitmapImageRep {
    let scale = max(1, panel.pixelsWide / Int(HeaderScrolledUnder.panelWidth))
    let gap = 28 * scale
    let total = panel.pixelsHigh + gap + stripPixels
    guard let dest = makeBitmap(
        pixelsWide: panel.pixelsWide,
        pixelsHigh: total,
        pointSize: NSSize(width: HeaderScrolledUnder.panelWidth, height: CGFloat(total) / CGFloat(scale))
    ) else {
        throw SnapshotError("could not compose the header strip")
    }
    let backdrop = panel.colorAt(x: 2, y: 2) ?? NSColor(srgbRed: 0.2, green: 0.2, blue: 0.2, alpha: 1)
    let cropY = panel.pixelsHigh + gap
    for y in panel.pixelsHigh..<cropY {
        for x in 0..<panel.pixelsWide {
            dest.setColor(backdrop, atX: x, y: y)
        }
    }
    for y in 0..<panel.pixelsHigh {
        for x in 0..<panel.pixelsWide {
            guard let color = panel.colorAt(x: x, y: y) else { continue }
            dest.setColor(color, atX: x, y: y)
        }
    }
    for y in 0..<stripPixels {
        for x in 0..<panel.pixelsWide {
            guard let color = panel.colorAt(x: x, y: y) else { continue }
            dest.setColor(color, atX: x, y: cropY + y)
        }
    }
    return dest
}

private extension NSView {
    func firstDescendant<T: NSView>(of type: T.Type) -> T? {
        if let match = self as? T { return match }
        for subview in subviews {
            if let match = subview.firstDescendant(of: type) { return match }
        }
        return nil
    }
}

private struct Bitmap {
    var width: Int
    var height: Int
    var pixels: [UInt8]

    init(_ url: URL) throws {
        guard let rep = NSBitmapImageRep(data: try Data(contentsOf: url)) else {
            throw SnapshotError("could not read \(url.lastPathComponent)")
        }
        try self.init(rep)
    }

    init(_ rep: NSBitmapImageRep) throws {
        guard let cg = rep.cgImage else { throw SnapshotError("bitmap has no image") }
        width = cg.width
        height = cg.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw SnapshotError("could not read pixels")
        }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        pixels = buffer
    }

    func averageRow(where matches: ((r: UInt8, g: UInt8, b: UInt8)) -> Bool) -> Int? {
        var sum = 0
        var count = 0
        for y in 0..<height {
            for x in stride(from: 0, to: width, by: 2) {
                let p = pixel(x, y)
                if matches(p) {
                    sum += y
                    count += 1
                }
            }
        }
        guard count > 20 else { return nil }
        return sum / count
    }

    /// y is measured from the top. The context's origin is the bottom.
    func pixel(_ x: Int, _ yFromTop: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let y = height - 1 - yFromTop
        let i = (y * width + x) * 4
        return (pixels[i], pixels[i + 1], pixels[i + 2])
    }

    func quoteBarRuns() -> [Range<Int>] {
        var rows: [Int] = []
        for y in 0..<height {
            var blues = 0
            for x in 0..<width {
                let p = pixel(x, y)
                if abs(Int(p.r) - 138) < 40, abs(Int(p.g) - 180) < 40, Int(p.b) > 200, Int(p.b) > Int(p.r) + 40 {
                    blues += 1
                }
            }
            if blues >= 2 { rows.append(y) }
        }
        var runs: [Range<Int>] = []
        var start: Int?
        var previous: Int?
        for y in rows {
            if let previous, y == previous + 1 {
                // still in the run
            } else {
                if let start, let previous {
                    runs.append(start..<previous + 1)
                }
                start = y
            }
            previous = y
        }
        if let start, let previous {
            runs.append(start..<previous + 1)
        }
        return runs
    }

    /// Rows that are not the backdrop. The ends are the content, whichever
    /// way the bitmap numbers its rows.
    func contentYRange(background: (UInt8, UInt8, UInt8)? = nil, slack: Int = 18) -> ClosedRange<Int>? {
        let bg = background ?? backdrop()
        var minY: Int?
        var maxY = 0
        let step = max(1, width / 180)
        for y in 0..<height {
            for x in stride(from: 4, to: max(5, width - 4), by: step) {
                let p = pixel(x, y)
                if abs(Int(p.r) - Int(bg.0)) > slack
                    || abs(Int(p.g) - Int(bg.1)) > slack
                    || abs(Int(p.b) - Int(bg.2)) > slack {
                    if minY == nil { minY = y }
                    maxY = y
                    break
                }
            }
        }
        guard let minY else { return nil }
        return minY...maxY
    }

    /// The colour that covers most of the image. A corner can be the chip.
    private func backdrop() -> (UInt8, UInt8, UInt8) {
        var counts: [Int: Int] = [:]
        let step = max(1, width / 40)
        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                let p = pixel(x, y)
                let key = (Int(p.r) / 8) << 16 | (Int(p.g) / 8) << 8 | (Int(p.b) / 8)
                counts[key, default: 0] += 1
            }
        }
        let key = counts.max { $0.value < $1.value }?.key ?? 0
        return (UInt8((key >> 16) * 8 + 4), UInt8(((key >> 8) & 0xff) * 8 + 4), UInt8((key & 0xff) * 8 + 4))
    }

    /// How far the quote ink starts past the card's left edge, in pixels.
    func quoteTextInset() -> Int? {
        let corner = pixel(min(2, width - 1), min(2, height - 1))
        var bestInset: Int?
        let step = 2
        for y in stride(from: 8, to: height - 8, by: step) {
            var cardLeft: Int?
            var cardRight = 0
            var x = 0
            while x < width {
                let p = pixel(x, y)
                if isCardFill(p, background: corner) {
                    if cardLeft == nil { cardLeft = x }
                    cardRight = x
                }
                x += 1
            }
            guard let left = cardLeft, cardRight - left > 80 else { continue }
            var textX: Int?
            for x in left...cardRight {
                let p = pixel(x, y)
                let luma = (Int(p.r) + Int(p.g) + Int(p.b)) / 3
                let bg = (Int(corner.r) + Int(corner.g) + Int(corner.b)) / 3
                if luma > bg + 70 {
                    textX = x
                    break
                }
            }
            guard let textX else { continue }
            let inset = textX - left
            if bestInset == nil || inset < bestInset! {
                bestInset = inset
            }
        }
        return bestInset
    }

    private func isCardFill(_ p: (r: UInt8, g: UInt8, b: UInt8), background: (r: UInt8, g: UInt8, b: UInt8)) -> Bool {
        let neutral = abs(Int(p.r) - Int(p.g)) < 12 && abs(Int(p.g) - Int(p.b)) < 12
        let lift = Int(p.r) - Int(background.r)
        return neutral && lift > 6 && lift < 36
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
        suggest(alreadyAsked: [])
    }

    /// The answer to "What does Theorem 5.4 build on?" does not offer that
    /// question again. The proof question is a different ask and stays.
    var withoutTheQuestionJustAsked: [SuggestedFollowUp] {
        suggest(alreadyAsked: ["What does Theorem 5.4 build on?"])
    }

    private func suggest(alreadyAsked: [String]) -> [SuggestedFollowUp] {
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
            statements: statements,
            alreadyAsked: alreadyAsked
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
        let filtered = withoutTheQuestionJustAsked
        guard filtered.map(\.question) == ["Why does the proof of Proposition 5.3 need compactness?"] else {
            throw SnapshotError("the question just asked was offered again: \(filtered.map(\.question))")
        }
        let paraphrased = suggest(alreadyAsked: ["What is Theorem 5.4 built on?"])
        guard paraphrased.map(\.question) == filtered.map(\.question) else {
            throw SnapshotError("a paraphrase of the question just asked was offered: \(paraphrased.map(\.question))")
        }
    }
}

@MainActor
private func renderJerry152(to output: URL) throws {
    let plainURL = output.appendingPathComponent("jerry-152-line-plain.png")
    let citedURL = output.appendingPathComponent("jerry-152-line-cited.png")
    try writePNG(CitationLineProbe(cited: false), to: plainURL, minimumBytes: 400, minimumSide: 8)
    try writePNG(CitationLineProbe(cited: true), to: citedURL, minimumBytes: 400, minimumSide: 8)
    let plain = try Bitmap(plainURL)
    let cited = try Bitmap(citedURL)
    guard plain.height == cited.height else {
        throw SnapshotError("a line with a citation is \(cited.height)px and a line without is \(plain.height)px")
    }
    fputs("citation line matches the plain line at \(plain.height)px\n", stdout)
    try writePNG(
        CitationLinePair(),
        to: output.appendingPathComponent("jerry-152-citation-line-height.png"),
        minimumBytes: 1_000
    )

    let hoverExcerpt = "If X is a set with the discrete metric, every set is open. The rest of this synthetic passage is only on the hover card, past the two lines the chip keeps."
    let hoverPassage = PinnedPassage(
        pageIndex: 36,
        excerpt: hoverExcerpt,
        fingerprint: "jerry-152-hover",
        bounds: NormalizedRect(x: 0.08, y: 0.42, width: 0.84, height: 0.08)
    )
    let stackedURL = output.appendingPathComponent("jerry-152-hover-stacked.png")
    let floatingURL = output.appendingPathComponent("jerry-152-hover-floating.png")
    let transcriptURL = output.appendingPathComponent("jerry-152-hover-transcript.png")
    // Three places the card actually opens: the composer chip, a chip already
    // in the transcript, and the chip on a sent message. Same card, different views.
    try writePNG(ComposerHoverShot(passage: hoverPassage), to: stackedURL, minimumBytes: 2_000)
    try writePNG(TranscriptHoverShot(passage: hoverPassage), to: floatingURL, minimumBytes: 2_000)
    try writePNG(SentChipHoverShot(passage: hoverPassage), to: transcriptURL, minimumBytes: 2_000)
    try assertCardIsOneShape(in: stackedURL)
    try assertCardIsOneShape(in: floatingURL)
    try assertCardIsOneShape(in: transcriptURL)
    try assertDistinctRenders([stackedURL, floatingURL, transcriptURL])

    let firstURL = output.appendingPathComponent("jerry-152-first-answer.png")
    try writePNG(FirstLaunchAnswer(), to: firstURL, minimumBytes: 2_000)
    try assertFirstAnswerIsLinked(in: firstURL)

    try assertChipBlocksTheTranscript()
    try renderScrolledChip(to: output.appendingPathComponent("jerry-152-scrolled-chip.png"))
}

/// One line of body text, with the page pill and without it.
private struct CitationLineProbe: View {
    var cited: Bool

    var body: some View {
        ReferenceLinkedText(
            text: "The set is closed.",
            chips: cited
                ? [AnswerSourceMarkers.Chip(sourceID: "R1", pageIndex: 38, pageLabel: "39")]
                : []
        )
        .frame(width: 360, alignment: .leading)
        .padding(16)
        .background(Color(white: 0.12))
        .environment(\.colorScheme, .dark)
    }
}

private struct CitationLinePair: View {
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            CitationLineProbe(cited: false)
            CitationLineProbe(cited: true)
        }
        .padding(20)
        .background(Color(white: 0.1))
        .environment(\.colorScheme, .dark)
    }
}

/// The card open on the composer chip: filled quote, dismiss control, and the
/// ask field underneath. This is not the transcript chip.
private struct ComposerHoverShot: View {
    var passage: PinnedPassage

    var body: some View {
        VStack(alignment: .leading, spacing: ConversationChrome.passageChipComposerSpacing) {
            PassageChipView(
                passage: passage,
                role: .composer,
                showsHoverCard: true,
                onOpen: {},
                onDismiss: {}
            )
            SnapshotComposerBar()
        }
        .padding(24)
        .frame(width: 420, alignment: .leading)
        .background(Color(white: 0.15))
        .environment(\.colorScheme, .dark)
    }
}

/// The card open on a chip that already sits in the thread, with the question
/// and the reply still on screen. The chip has no fill and no dismiss control.
private struct TranscriptHoverShot: View {
    var passage: PinnedPassage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PassageChipView(
                passage: passage,
                role: .transcript,
                showsHoverCard: true,
                onOpen: {},
                onDismiss: {}
            )
            Text("Does the discrete metric make every set open?")
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18))
                .frame(maxWidth: 280, alignment: .trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text("Yes. In the discrete metric the open balls are singletons, so every set is a union of open balls.")
                .font(.body)
                .foregroundStyle(.primary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ContentSurface.bubble, in: RoundedRectangle(cornerRadius: 18))
        }
        .padding(24)
        .frame(width: 460, alignment: .leading)
        .background(Color(white: 0.12))
        .environment(\.colorScheme, .dark)
    }
}

/// The card open on the chip of a message that was just sent. The real
/// message row: the quote, then the blue question, trailing in the panel.
private struct SentChipHoverShot: View {
    var passage: PinnedPassage

    var body: some View {
        MessageBubble(
            message: ThreadMessage(
                role: .user,
                content: "Is every subset open?",
                passage: MessagePassage(pageIndex: passage.pageIndex, excerpt: passage.excerpt)
            ),
            maxBubbleWidth: 300,
            showsPassageCard: true
        )
        .padding(24)
        .frame(width: 420, alignment: .trailing)
        .background(Color(white: 0.1))
        .environment(\.colorScheme, .dark)
    }
}

@MainActor
private func assertDistinctRenders(_ urls: [URL]) throws {
    var seen: [Data: String] = [:]
    for url in urls {
        let data = try Data(contentsOf: url)
        if let previous = seen[data] {
            throw SnapshotError("\(url.lastPathComponent) is the same render as \(previous)")
        }
        seen[data] = url.lastPathComponent
    }
    fputs("hover cards are three different renders\n", stdout)
}

/// Cold launch: the index is not ready and the key set is empty. The
/// proposition is still a link.
private struct FirstLaunchAnswer: View {
    var body: some View {
        MessageBubble(
            message: ThreadMessage(
                role: .assistant,
                content: "By Proposition 5.3.1, the complement of an open set is closed."
            ),
            maxBubbleWidth: 320,
            referenceKeys: [],
            referenceIndexReady: false
        )
        .padding(28)
        .frame(width: 400, alignment: .leading)
        .background(Color(white: 0.12))
        .environment(\.colorScheme, .dark)
    }
}

/// Red sits behind the composer. An opaque chip area keeps every red pixel covered.
private struct ChipOcclusionProbe: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.red
            VStack(alignment: .leading, spacing: ConversationChrome.passageChipComposerSpacing) {
                PassageChipView(
                    passage: PinnedPassage(
                        pageIndex: 10,
                        excerpt: "A synthetic passage pinned above the composer.",
                        fingerprint: "jerry-152-occlude",
                        bounds: nil
                    ),
                    role: .composer,
                    onOpen: {},
                    onDismiss: {}
                )
                SnapshotComposerBar()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .background(ConversationChrome.headerBackdrop)
        }
        .frame(width: 390, height: 220)
        .environment(\.colorScheme, .dark)
    }
}

@MainActor
private func assertChipBlocksTheTranscript() throws {
    let renderer = ImageRenderer(content: ChipOcclusionProbe().environment(\.displayScale, 2))
    renderer.scale = 2
    renderer.isOpaque = true
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
        throw SnapshotError("chip occlusion probe produced no image")
    }
    let bitmap = try Bitmap(rep)
    var leaked = 0
    // The bottom of the probe is the chip and the composer. Red above that
    // band is the stand-in for the transcript; red inside it is text showing through.
    let band = max(0, bitmap.height - 120)
    for y in band..<bitmap.height {
        for x in 0..<bitmap.width {
            let p = bitmap.pixel(x, y)
            if p.r > 200, p.g < 60, p.b < 60 { leaked += 1 }
        }
    }
    guard leaked == 0 else {
        throw SnapshotError("the passage chip lets \(leaked) pixels of the transcript show through")
    }
    fputs("chip band hides the transcript\n", stdout)
}

@MainActor
private func assertFirstAnswerIsLinked(in url: URL) throws {
    let bitmap = try Bitmap(url)
    var links = 0
    for y in stride(from: 0, to: bitmap.height, by: 1) {
        for x in stride(from: 0, to: bitmap.width, by: 1) {
            let p = bitmap.pixel(x, y)
            if abs(Int(p.r) - 138) < 28, abs(Int(p.g) - 180) < 28, abs(Int(p.b) - 248) < 28 {
                links += 1
            }
        }
    }
    guard links > 12 else {
        throw SnapshotError("the first answer has \(links) link-coloured pixels; Proposition 5.3.1 is not a link")
    }
    fputs("first answer links (\(links) tinted pixels)\n", stdout)
}

/// No isolated horizontal rule above the card. A user bubble is accent blue
/// and is not that rule; the quote-bar scan matches those pixels.
@MainActor
private func assertCardIsOneShape(in url: URL) throws {
    let bitmap = try Bitmap(url)
    let backdrop = bitmap.pixel(2, 2)
    var cardTop: Int?
    for y in 0..<bitmap.height {
        var different = 0
        for x in stride(from: 8, to: bitmap.width - 8, by: 2) {
            if channelGap(bitmap.pixel(x, y), backdrop) > 14 { different += 1 }
        }
        if different > 12 {
            cardTop = y
            break
        }
    }
    guard let cardTop, cardTop > 4 else {
        let sample = bitmap.pixel(min(12, bitmap.width - 1), min(12, bitmap.height - 1))
        throw SnapshotError(
            "hover card did not draw in \(url.lastPathComponent) (\(bitmap.width)x\(bitmap.height), cardTop \(cardTop.map(String.init) ?? "none"), sample \(sample))"
        )
    }
    var ruleRows: [Int] = []
    for y in max(0, cardTop - 10)..<cardTop {
        var different = 0
        for x in stride(from: 8, to: bitmap.width - 8, by: 2) {
            if channelGap(bitmap.pixel(x, y), backdrop) > 14 { different += 1 }
        }
        if different > 12 { ruleRows.append(y) }
    }
    guard ruleRows.isEmpty else {
        throw SnapshotError("thin bar above the hover card in \(url.lastPathComponent) at \(ruleRows)")
    }
    // The card is the top of the shot. A chip with no card sits in the bottom third.
    guard cardTop < bitmap.height * 55 / 100 else {
        throw SnapshotError("hover card is missing from \(url.lastPathComponent) (content starts at \(cardTop) of \(bitmap.height))")
    }
    fputs("hover card is one shape in \(url.lastPathComponent)\n", stdout)
}

private struct ScrolledChipPanel: View {
    static let panelWidth: CGFloat = 390
    static let panelHeight: CGFloat = 640

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("What does a finite-dimensional norm remember?")
                        .font(.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(Self.answer)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ContentSurface.bubble, in: RoundedRectangle(cornerRadius: 18))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                JumpToLatestButton()
                    .background {
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: JerryFrameKey.self,
                                value: ["jump": geo.frame(in: .named("jerry-panel"))]
                            )
                        }
                    }
                    .padding(.bottom, ConversationChrome.jumpButtonGap)
            }

            VStack(alignment: .leading, spacing: ConversationChrome.passageChipComposerSpacing) {
                PassageChipView(
                    passage: PinnedPassage(
                        pageIndex: 10,
                        excerpt: "A norm on a finite-dimensional space is a continuous function, and every linear map is bounded.",
                        fingerprint: "jerry-152-scroll",
                        bounds: NormalizedRect(x: 0.08, y: 0.3, width: 0.8, height: 0.08)
                    ),
                    role: .composer,
                    onOpen: {},
                    onDismiss: {}
                )
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: JerryFrameKey.self,
                            value: ["chip": geo.frame(in: .named("jerry-panel"))]
                        )
                    }
                }
                SnapshotComposerBar()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ConversationChrome.headerBackdrop)
        }
        .coordinateSpace(name: "jerry-panel")
        .frame(width: Self.panelWidth, height: Self.panelHeight)
        .background(ConversationChrome.headerBackdrop)
        .environment(\.colorScheme, .dark)
    }

    static let answer = """
    A norm on a finite-dimensional space is a continuous function, and every linear map between those spaces is bounded. The operator norm is the smallest constant that works for every vector.

    Equivalence of norms follows from compactness of the unit sphere. Once two norms are equivalent, completeness transfers from one to the other. These paragraphs are the part of the answer still on screen after the reader has scrolled up.

    The last line of this answer sits just above the passage chip. The chip is solid, and this sentence does not run underneath it. The round chevron is the only control over the text.

    A further paragraph keeps the answer taller than the panel, so this shot is scrolled up from the latest line. Finite-dimensional normed spaces are complete, and a linear map out of one is continuous exactly when it is bounded. The chevron sits on these lines, and the lines stop at the chip.
    """
}

private struct JerryFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

@MainActor
private final class JerryFrameProbe {
    var frames: [String: CGRect] = [:]
}

@MainActor
private func renderScrolledChip(to url: URL) throws {
    if !NSApp.isRunning {
        NSApp.finishLaunching()
    }
    let policy = NSApp.activationPolicy()
    NSApp.setActivationPolicy(.accessory)
    defer { NSApp.setActivationPolicy(policy) }
    let probe = JerryFrameProbe()
    let root = ScrolledChipPanel()
        .onPreferenceChange(JerryFrameKey.self) { probe.frames = $0 }
    let size = NSSize(width: ScrolledChipPanel.panelWidth, height: ScrolledChipPanel.panelHeight)
    let hosted = try HostedPanel(root: root, size: size)
    defer { hosted.window.close() }
    pump(0.45)
    let jump = probe.frames["jump"] ?? .zero
    let chip = probe.frames["chip"] ?? .zero
    guard jump.width > 24, jump.width < 36, abs(jump.height - jump.width) < 2 else {
        throw SnapshotError("jump button is \(jump), not a 28pt circle")
    }
    guard abs(jump.midX - ScrolledChipPanel.panelWidth / 2) < 8 else {
        throw SnapshotError("jump button is not centred (\(jump.midX))")
    }
    let gap = chip.minY - jump.maxY
    guard gap > 6, gap < 12 else {
        throw SnapshotError("jump button sits \(gap)pt above the chip, not 8")
    }
    guard !jump.intersects(chip) else {
        throw SnapshotError("jump button overlaps the chip")
    }
    // ImageRenderer and cacheDisplay never composite Liquid Glass: the circle
    // comes back as a flat disc. screencapture reads the on-screen window,
    // which is where glassEffect and the text behind it actually appear.
    try placeOnScreen(hosted.window)
    pump(0.8)
    try screenCapture(hosted.window, to: url)
    try assertGlassShowsTheTextBehind(in: url, jump: jump)
    let bytes = try Data(contentsOf: url).count
    guard bytes >= 8_000 else {
        throw SnapshotError("scrolled chip snapshot is \(bytes) bytes")
    }
    fputs("wrote \(url.path) (\(bytes) bytes) jump \(jump) chip \(chip) via screencapture\n", stdout)
}

/// Puts the panel on the visible display so the window server can draw glass.
@MainActor
private func placeOnScreen(_ window: NSWindow) {
    window.sharingType = .readOnly
    window.hasShadow = false
    if let screen = NSScreen.main ?? NSScreen.screens.first {
        let visible = screen.visibleFrame
        let frame = window.frame
        window.setFrameOrigin(NSPoint(
            x: visible.midX - frame.width / 2,
            y: visible.midY - frame.height / 2
        ))
    }
    window.orderFrontRegardless()
    window.makeKeyAndOrderFront(nil)
}

/// `screencapture -l` of the live window. A view bitmap cannot stand in for it.
@MainActor
private func screenCapture(_ window: NSWindow, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-l", "\(window.windowNumber)", "-o", "-x", url.path]
    let pipe = Pipe()
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    let err = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: url.path) else {
        throw SnapshotError("screencapture of the live window failed (\(process.terminationStatus)) \(err)")
    }
}

/// The glass circle must carry the answer behind it. A flat fill has no
/// variation in the ring around the chevron.
@MainActor
private func assertGlassShowsTheTextBehind(in url: URL, jump: CGRect) throws {
    let bitmap = try Bitmap(url)
    let scale = CGFloat(bitmap.width) / ScrolledChipPanel.panelWidth
    guard scale > 0.5 else {
        throw SnapshotError("screencapture is \(bitmap.width)px wide")
    }
    let centerX = jump.midX * scale
    let centerY = jump.midY * scale
    let radius = jump.width * scale / 2
    let inner = radius * 0.42
    let outer = radius * 0.84
    var samples: [Int] = []
    let minX = max(0, Int(centerX - outer))
    let maxX = min(bitmap.width - 1, Int(centerX + outer))
    let minY = max(0, Int(centerY - outer))
    let maxY = min(bitmap.height - 1, Int(centerY + outer))
    for y in minY...maxY {
        for x in minX...maxX {
            let dx = CGFloat(x) - centerX
            let dy = CGFloat(y) - centerY
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance > inner, distance < outer {
                let pixel = bitmap.pixel(x, y)
                samples.append(Int(pixel.r) + Int(pixel.g) + Int(pixel.b))
            }
        }
    }
    guard samples.count > 20 else {
        throw SnapshotError("glass circle was not in the screencapture (\(samples.count) samples)")
    }
    let mean = samples.reduce(0, +) / samples.count
    let variance = samples.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / samples.count
    fputs("glass ring mean \(mean) variance \(variance) over \(samples.count) samples\n", stdout)
    guard variance > 36 else {
        throw SnapshotError("the chevron is a flat disc (ring variance \(variance)); glass is not showing the text behind it")
    }
}

@MainActor
private func windowBitmap(of window: NSWindow) -> NSBitmapImageRep? {
    let windowID = CGWindowID(window.windowNumber)
    guard let image = CGWindowListCreateImage(
        .null,
        .optionIncludingWindow,
        windowID,
        [.boundsIgnoreFraming, .bestResolution]
    ) else { return nil }
    let rep = NSBitmapImageRep(cgImage: image)
    guard bitmapHasInk(rep) else { return nil }
    return rep
}

@MainActor
private func scaleBitmapPixels(_ source: NSBitmapImageRep, by factor: Int) throws -> NSBitmapImageRep {
    if factor == 1 { return source }
    let width = source.pixelsWide * factor
    let height = source.pixelsHigh * factor
    guard let dest = makeBitmap(
        pixelsWide: width,
        pixelsHigh: height,
        pointSize: NSSize(width: CGFloat(width) / 2, height: CGFloat(height) / 2)
    ) else {
        throw SnapshotError("could not scale the scrolled chip snapshot")
    }
    for y in 0..<source.pixelsHigh {
        for x in 0..<source.pixelsWide {
            guard let color = source.colorAt(x: x, y: y) else { continue }
            for dy in 0..<factor {
                for dx in 0..<factor {
                    dest.setColor(color, atX: x * factor + dx, y: y * factor + dy)
                }
            }
        }
    }
    return dest
}

private struct SnapshotError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

@MainActor
private func writePNG<V: View>(_ view: V, to url: URL, minimumBytes: Int, minimumSide: Int = 80) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let renderer = ImageRenderer(content: view.environment(\.displayScale, 2))
    renderer.scale = 2
    renderer.isOpaque = true
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        throw SnapshotError("ImageRenderer produced no PNG")
    }
    guard png.count >= minimumBytes, rep.pixelsWide > minimumSide, rep.pixelsHigh > minimumSide else {
        throw SnapshotError("PNG is \(png.count) bytes, \(rep.pixelsWide)x\(rep.pixelsHigh)")
    }
    try png.write(to: url)
    fputs("wrote \(url.path) (\(png.count) bytes, \(rep.pixelsWide)x\(rep.pixelsHigh))\n", stdout)
}
