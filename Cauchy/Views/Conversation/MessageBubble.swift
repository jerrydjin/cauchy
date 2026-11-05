import AppKit
import SwiftUI

struct MessageBubble: View {
    let message: ThreadMessage
    var quotedText: String?
    var maxBubbleWidth: CGFloat = 300
    var onOpenSource: (AnswerSourceAnchor) -> Void = { _ in }
    var referenceKeys: Set<ReferenceKey> = []
    /// False on the first paint of a cold launch, before the reference index
    /// has loaded. References are still links; see `presentedReferences`.
    var referenceIndexReady = true
    var onOpenReference: (DetectedReference) -> Void = { _ in }
    /// Grounded next questions. Empty while an answer is still streaming, and
    /// empty when the document does not support a real next step.
    var followUps: [SuggestedFollowUp] = []
    /// The snapshot shows the pills at rest. A live answer fades them in
    /// after the text is committed, without changing the bubble's height.
    var followUpsStartVisible = false
    /// The snapshot opens the passage card on a sent message. A live chip
    /// opens the same card on hover.
    var showsPassageCard = false
    var onAskFollowUp: (String) -> Void = { _ in }

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        if !isUser, !followUps.isEmpty {
            VStack(alignment: .leading, spacing: ConversationChrome.answerFollowUpGap) {
                bubbleRow
                FollowUpPills(
                    followUps: followUps,
                    maxWidth: maxBubbleWidth,
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

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                if isUser, let passage = message.passage {
                    PassageChipView(
                        passage: passage.pinned,
                        role: .transcript,
                        maxWidth: maxBubbleWidth,
                        showsHoverCard: showsPassageCard,
                        onOpen: {}
                    )
                }
                if showsQuestionBubble {
                    styledBubble
                        .background { sentBubbleFrame }
                }
            }
            // Alignment inside the frame is what actually sides the bubble:
            // the frame fills whatever the row offers, so relying on the
            // leftover width to push a user message right stops working as
            // soon as the bubble is allowed to be as wide as the panel.
            .frame(maxWidth: maxBubbleWidth, alignment: isUser ? .trailing : .leading)
            .fixedSize(horizontal: false, vertical: true)

            if !isUser { Spacer(minLength: ConversationChrome.bubbleHorizontalInset) }
        }
        .coordinateSpace(name: "sent-passage")
        .background { sentRowFrame }
    }

    private var sentBubbleFrame: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: SentPassageFrameKey.self,
                value: ["bubble": geo.frame(in: .named("sent-passage"))]
            )
        }
    }

    private var sentRowFrame: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: SentPassageFrameKey.self,
                value: ["row": geo.frame(in: .named("sent-passage"))]
            )
        }
    }

    /// Flat fill, not glass: a bubble is content, and content sits below the
    /// glass layer rather than joining it. See ContentSurface. The passage
    /// chip stays outside this fill so it keeps the composer's quiet colour.
    private var styledBubble: some View {
        bubbleContent
            .padding(.horizontal, isUser ? ConversationChrome.bubbleContentPaddingH : ConversationChrome.answerPaddingH)
            .padding(.vertical, isUser ? ConversationChrome.bubbleContentPaddingV : ConversationChrome.answerPaddingV)
            .background(
                isUser ? Color.accentColor : ContentSurface.bubble,
                in: RoundedRectangle(cornerRadius: ConversationChrome.bubbleCornerRadius)
            )
            // Answers render as a stack of separate text and math views, so
            // dragging a selection can never pick up a whole reply — copy
            // the source text instead.
            .contextMenu {
                if !message.content.isEmpty {
                    Button("Copy Message") { copyToPasteboard(message.content) }
                }
                if let excerpt = message.passage?.excerpt, !excerpt.isEmpty {
                    Button("Copy Quoted Passage") { copyToPasteboard(excerpt) }
                } else if let quotedText, !quotedText.isEmpty {
                    Button("Copy Quoted Passage") { copyToPasteboard(quotedText) }
                }
            }
    }

    private var showsQuestionBubble: Bool {
        if !message.content.isEmpty || !isUser { return true }
        return message.passage == nil && !(quotedText?.isEmpty ?? true)
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @ViewBuilder
    private var bubbleContent: some View {
        if isUser, message.passage == nil, let quotedText, !quotedText.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SelectionQuoteView(text: quotedText)
                if !message.content.isEmpty {
                    Divider().opacity(0.25)
                    MessageContentView(
                        content: message.content,
                        font: .body,
                        textColor: .primary,
                        referenceKeys: referenceKeys,
                        referenceIndexReady: referenceIndexReady,
                        onOpenReference: onOpenReference
                    )
                }
            }
        } else {
            MessageContentView(
                content: message.content,
                font: .body,
                textColor: .primary,
                referenceKeys: referenceKeys,
                referenceIndexReady: referenceIndexReady,
                onOpenReference: onOpenReference,
                interpretsSourceMarkers: !isUser,
                sourceAnchors: message.answerEvidence?.sourceAnchors ?? [],
                onOpenSource: onOpenSource
            )
        }
    }
}

/// Suggested questions sit under the bubble, on its left edge, one pill per
/// line. A pill is as wide as its question, and no wider than the bubble.
/// They are the next thing to ask, not part of the answer. The whole pill
/// is one button, and the only words on it are the question. The pills take
/// their height while they fade, so the answer does not jump when they appear.
struct FollowUpPills: View {
    var followUps: [SuggestedFollowUp]
    var maxWidth: CGFloat
    var startsVisible: Bool
    var onAsk: (String) -> Void

    @State private var shown: Bool

    init(
        followUps: [SuggestedFollowUp],
        maxWidth: CGFloat,
        startsVisible: Bool,
        onAsk: @escaping (String) -> Void
    ) {
        self.followUps = followUps
        self.maxWidth = maxWidth
        self.startsVisible = startsVisible
        self.onAsk = onAsk
        _shown = State(initialValue: startsVisible)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ConversationChrome.answerFollowUpSpacing) {
            ForEach(followUps) { followUp in
                FollowUpPill(followUp: followUp, maxWidth: maxWidth, onAsk: onAsk)
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
    var maxWidth: CGFloat
    var onAsk: (String) -> Void

    @State private var isHovered = false

    var body: some View {
        // The layout, not the button, decides the width. A button proposed the
        // bubble's width would stretch a short question into a full-width bar.
        FollowUpPillLayout(maxWidth: maxWidth) {
            questionLabel
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .accessibilityHidden(true)
                .padding(.horizontal, ConversationChrome.answerFollowUpPaddingH)
                .padding(.vertical, ConversationChrome.answerFollowUpPaddingV)
                .frame(minHeight: 28)
                .background {
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
                }
        }
        .overlay {
            Button {
                onAsk(followUp.question)
            } label: {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .citationLinkHover($isHovered)
            .accessibilityLabel(followUp.voiceOverLabel)
        }
    }

    /// The question underlines with the pill.
    private var questionLabel: Text {
        guard isHovered else { return Text(followUp.question) }
        var attributed = AttributedString(followUp.question)
        attributed.underlineStyle = Text.LineStyle(pattern: .solid, color: .secondary)
        return Text(attributed)
    }
}

/// Width of the question, stopping at the bubble. A short question stays on
/// one line. A longer one wraps inside that width.
private struct FollowUpPillLayout: Layout {
    var maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let limit = min(proposal.width ?? maxWidth, maxWidth)
        let ideal = subview.sizeThatFits(.unspecified)
        if ideal.width <= limit || limit <= 0 {
            return ideal
        }
        let wrapped = subview.sizeThatFits(ProposedViewSize(width: limit, height: nil))
        return CGSize(width: min(wrapped.width, limit), height: wrapped.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        subview.place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
    }
}
