import AppKit
import SwiftUI

struct MessageBubble: View {
    let message: ThreadMessage
    var quotedText: String?
    var maxBubbleWidth: CGFloat = 300
    var onOpenSource: (AnswerSourceAnchor) -> Void = { _ in }
    var referenceKeys: Set<ReferenceKey> = []
    var onOpenReference: (DetectedReference) -> Void = { _ in }
    /// The designer snapshot opens the sources line. A live answer starts closed.
    var sourcesStartExpanded = false
    /// Grounded next questions. Empty while an answer is still streaming, and
    /// empty when the document does not support a real next step.
    var followUps: [SuggestedFollowUp] = []
    /// The snapshot shows the pills at rest. A live answer fades them in
    /// after the text is committed, without changing the bubble's height.
    var followUpsStartVisible = false
    var onAskFollowUp: (String) -> Void = { _ in }

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        if !isUser, !followUps.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                bubbleRow
                FollowUpPills(
                    followUps: followUps,
                    startsVisible: followUpsStartVisible,
                    onAsk: onAskFollowUp
                )
                .frame(maxWidth: maxBubbleWidth, alignment: .leading)
            }
        } else {
            bubbleRow
        }
    }

    private var bubbleRow: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: ConversationChrome.bubbleHorizontalInset) }

            bubbleContent
                .padding(.horizontal, ConversationChrome.bubbleContentPaddingH)
                .padding(.vertical, ConversationChrome.bubbleContentPaddingV)
                // Flat fill, not glass: a bubble is content, and content sits
                // below the glass layer rather than joining it. See ContentSurface.
                .background(
                    isUser ? Color.accentColor : ContentSurface.bubble,
                    in: RoundedRectangle(cornerRadius: ConversationChrome.bubbleCornerRadius)
                )
                // Alignment inside the frame is what actually sides the bubble:
                // the frame fills whatever the row offers, so relying on the
                // leftover width to push a user message right stops working as
                // soon as the bubble is allowed to be as wide as the panel.
                .frame(maxWidth: maxBubbleWidth, alignment: isUser ? .trailing : .leading)
                .fixedSize(horizontal: false, vertical: true)
                // Answers render as a stack of separate text and math views, so
                // dragging a selection can never pick up a whole reply — copy
                // the source text instead.
                .contextMenu {
                    if !message.content.isEmpty {
                        Button("Copy Message") { copyToPasteboard(message.content) }
                    }
                    if let quotedText, !quotedText.isEmpty {
                        Button("Copy Quoted Passage") { copyToPasteboard(quotedText) }
                    }
                }

            if !isUser { Spacer(minLength: ConversationChrome.bubbleHorizontalInset) }
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @ViewBuilder
    private var bubbleContent: some View {
        if isUser, let quotedText, !quotedText.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SelectionQuoteView(text: quotedText)
                if !message.content.isEmpty {
                    Divider().opacity(0.25)
                    MessageContentView(
                        content: message.content,
                        font: .body,
                        textColor: .primary,
                        referenceKeys: referenceKeys,
                        onOpenReference: onOpenReference
                    )
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                MessageContentView(
                    content: message.content,
                    font: .body,
                    textColor: .primary,
                    referenceKeys: referenceKeys,
                    onOpenReference: onOpenReference,
                    interpretsSourceMarkers: !isUser,
                    sourceAnchors: message.answerEvidence?.sourceAnchors ?? [],
                    onOpenSource: onOpenSource
                )
                if !isUser {
                    let pages = CitedSourceSummary.pages(
                        in: message.content,
                        anchors: message.answerEvidence?.sourceAnchors ?? []
                    )
                    if !pages.isEmpty {
                        CitedSourcesDisclosure(
                            pages: pages,
                            startExpanded: sourcesStartExpanded,
                            onOpen: onOpenSource
                        )
                    }
                }
            }
        }
    }
}

/// Suggested questions sit under the bubble, on its left edge, one pill per
/// line. They are the next thing to ask, not part of the answer. The whole
/// pill is one button. A page mark inside it only shows where the question
/// points. The pills take their height while they fade, so the answer does
/// not jump when they appear.
struct FollowUpPills: View {
    var followUps: [SuggestedFollowUp]
    var startsVisible: Bool
    var onAsk: (String) -> Void

    @State private var shown: Bool

    init(
        followUps: [SuggestedFollowUp],
        startsVisible: Bool,
        onAsk: @escaping (String) -> Void
    ) {
        self.followUps = followUps
        self.startsVisible = startsVisible
        self.onAsk = onAsk
        _shown = State(initialValue: startsVisible)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(followUps) { followUp in
                FollowUpPill(followUp: followUp, onAsk: onAsk)
            }
        }
        .opacity(shown ? 1 : 0)
        .accessibilityHidden(!shown)
        .onAppear {
            guard !startsVisible, !shown else { return }
            withAnimation(.easeIn(duration: 0.35)) {
                shown = true
            }
        }
    }
}

struct FollowUpPill: View {
    var followUp: SuggestedFollowUp
    var onAsk: (String) -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            onAsk(followUp.question)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                questionLabel
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let pageLabel = followUp.pageLabel {
                    pageMark(pageLabel)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(minHeight: 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .citationLinkHover($isHovered)
        .accessibilityLabel(followUp.voiceOverLabel)
        .background {
            Capsule()
                .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
        }
    }

    /// The question underlines with the pill. The page mark never does.
    private var questionLabel: Text {
        guard isHovered else { return Text(followUp.question) }
        var attributed = AttributedString(followUp.question)
        attributed.underlineStyle = Text.LineStyle(pattern: .solid, color: .secondary)
        return Text(attributed)
    }

    /// Display only: the same number and arrow as a claim tag, with no action.
    private func pageMark(_ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(label)
            Text(Image(systemName: "arrow.up.right"))
                .accessibilityHidden(true)
        }
        .font(.callout)
        .foregroundStyle(CitationChrome.tint)
        .accessibilityHidden(true)
        .fixedSize()
    }
}

/// Closed on every new answer. Collapsed it is a hairline pill with no
/// fill of its own, so the bubble colour shows through. The label is
/// "Sources · N pages" with a chevron, in the link tint. Expanded, the
/// page tags sit on one line with one em of the caption face between them.
struct CitedSourcesDisclosure: View {
    var pages: [CitedSourcePage]
    var startExpanded: Bool
    var onOpen: (AnswerSourceAnchor) -> Void

    @State private var isExpanded: Bool
    @State private var isPillHovered = false

    init(
        pages: [CitedSourcePage],
        startExpanded: Bool = false,
        onOpen: @escaping (AnswerSourceAnchor) -> Void
    ) {
        self.pages = pages
        self.startExpanded = startExpanded
        self.onOpen = onOpen
        _isExpanded = State(initialValue: startExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 5) {
                    pillLabel
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .font(.caption)
                .foregroundStyle(CitationChrome.tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(minHeight: 28)
                .background {
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .citationLinkHover($isPillHovered)
            .accessibilityLabel(CitedSourceSummary.disclosureLabel(pageCount: pages.count))
            .accessibilityValue(isExpanded ? "expanded" : "collapsed")

            if isExpanded {
                InlineFlowLayout(horizontalSpacing: 0, verticalSpacing: 2) {
                    ForEach(Array(lineTokens.enumerated()), id: \.offset) { _, token in
                        if let page = token.page {
                            PageTagButton(
                                chip: AnswerSourceMarkers.Chip(
                                    sourceID: page.anchor.sourceID ?? "",
                                    pageIndex: page.pageIndex,
                                    pageLabel: page.pageLabel
                                ),
                                anchor: page.anchor,
                                onOpen: onOpen,
                                font: .caption,
                                leadingPadding: 0
                            )
                        } else {
                            Text(token.title)
                                .font(.caption)
                                .accessibilityHidden(true)
                                .fixedSize()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The pill's words. Underlined only while the pointer is over the pill,
    /// so the resting label is the same text as before.
    private var pillLabel: Text {
        let title = CitedSourceSummary.disclosureLabel(pageCount: pages.count)
        guard isPillHovered else { return Text(title) }
        var attributed = AttributedString(title)
        attributed.underlineStyle = Text.LineStyle(pattern: .solid, color: CitationChrome.tint)
        return Text(attributed)
    }

    private var lineTokens: [(title: String, page: CitedSourcePage?)] {
        var tokens: [(title: String, page: CitedSourcePage?)] = []
        for (index, page) in pages.enumerated() {
            if index > 0 {
                // One em of the caption face, in place of a comma. Hidden
                // from VoiceOver so each page tag is announced on its own.
                tokens.append(("\u{2003}", nil))
            }
            tokens.append((page.pageLabel, page))
        }
        return tokens
    }
}
