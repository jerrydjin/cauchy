import SwiftUI

/// The conversation. The header is a `safeAreaBar`: messages pass beneath
/// that glass, and the scroll edge effect keeps the title legible.
///
/// The composer is not. The passage chip is solid and sits in the composer's
/// opaque area, and the transcript ends above that area so nothing scrolls
/// under the quote. The jump control is the glass layer: a round chevron,
/// centred 8pt above the chip (or above the composer when there is no chip),
/// and text may pass behind it.
struct ConversationPanel<Header: View>: View {
    let selectedText: String?
    let messages: [ThreadMessage]
    var streamingText: String?
    var isResponding: Bool
    var canAsk: Bool
    var unavailableMessage: String?
    var recoveryTitle: String?
    var failureMessage: String?
    var panelWidth: CGFloat
    @Binding var question: String
    var onSend: () -> Void
    var onStop: () -> Void = {}
    var onModelChange: () -> Void = {}
    var pinnedPassage: PinnedPassage? = nil
    var onOpenPassage: () -> Void = {}
    var onDismissPassage: () -> Void = {}
    var onRecovery: () -> Void = {}
    var onOpenSource: (AnswerSourceAnchor) -> Void = { _ in }
    var referenceKeys: Set<ReferenceKey> = []
    var referenceIndexReady = true
    var onOpenReference: (DetectedReference) -> Void = { _ in }
    var followUpsFor: (ThreadMessage) -> [SuggestedFollowUp] = { _ in [] }
    var onAskFollowUp: (String) -> Void = { _ in }
    @ViewBuilder var header: Header

    @State private var followsLatest = true
    @State private var userIsScrolling = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                transcript(proxy: proxy)
            }
            composerBar
                .background(ConversationChrome.headerBackdrop)
        }
        .background(ConversationChrome.headerBackdrop)
    }

    private func transcript(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if messages.isEmpty, !isResponding {
                    Text("Ask a question about this passage")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .id("empty-state")
                }

                ForEach(messages) { message in
                    MessageBubble(
                        message: message,
                        quotedText: nil,
                        maxBubbleWidth: bubbleWidth,
                        onOpenSource: onOpenSource,
                        referenceKeys: referenceKeys,
                        referenceIndexReady: referenceIndexReady,
                        onOpenReference: onOpenReference,
                        followUps: ConversationFollowUps.shouldShow(
                            on: message,
                            in: messages,
                            isResponding: isResponding
                        ) ? followUpsFor(message) : [],
                        onAskFollowUp: onAskFollowUp
                    )
                    .id(message.id)
                }

                if isResponding, let streamingText, !streamingText.isEmpty {
                    MessageBubble(
                        message: ThreadMessage(role: .assistant, content: streamingText),
                        maxBubbleWidth: bubbleWidth,
                        referenceKeys: referenceKeys,
                        referenceIndexReady: referenceIndexReady,
                        onOpenReference: onOpenReference
                    )
                    .id("streaming")
                }

                if let failureMessage, !failureMessage.isEmpty, !isResponding {
                    Text(failureMessage)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .padding(.horizontal, ConversationChrome.bubbleContentPaddingH)
                        .padding(.vertical, ConversationChrome.bubbleContentPaddingV)
                        .background(Color.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: ConversationChrome.bubbleCornerRadius))
                        .frame(maxWidth: bubbleWidth, alignment: .leading)
                        .id("failure")
                }

                if isResponding,
                   streamingText == nil || streamingText?.isEmpty == true {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 8)
                        .id("thinking")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 80
        } action: { _, nearBottom in
            if userIsScrolling { followsLatest = nearBottom }
        }
        .onScrollPhaseChange { oldPhase, newPhase, context in
            userIsScrolling = newPhase == .interacting || newPhase == .decelerating
            if newPhase == .idle && (oldPhase == .interacting || oldPhase == .decelerating) {
                let geometry = context.geometry
                followsLatest = geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 80
            }
        }
        .overlay(alignment: .bottom) {
            // Centred on the transcript, 8pt above the chip. Text may pass
            // behind the glass. The chip is outside this scroll view, so the
            // button cannot cover it. It fades out once the reader is at the bottom.
            JumpToLatestButton {
                followsLatest = true
                scrollToBottom(proxy: proxy)
            }
            .padding(.bottom, ConversationChrome.jumpButtonGap)
            .opacity(followsLatest ? 0 : 1)
            .allowsHitTesting(!followsLatest)
            .accessibilityHidden(followsLatest)
            .animation(.easeOut(duration: 0.2), value: followsLatest)
        }
        .safeAreaBar(edge: .top) {
            header
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ConversationChrome.headerBackdrop)
        }
        // `.soft` under the header only. The bottom edge is a hard stop at
        // the opaque composer, so a soft blur cannot draw the transcript
        // through the chip.
        .scrollEdgeEffectStyle(.soft, for: .top)
        .onAppear {
            scrollToBottom(proxy: proxy)
        }
        .onChange(of: messages.count) { _, _ in
            if messages.last?.role == .user { followsLatest = true }
            if followsLatest { scrollToBottom(proxy: proxy) }
        }
        .onChange(of: streamingText) { _, _ in
            if followsLatest { scrollToBottom(proxy: proxy) }
        }
    }

    private var composerBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let unavailableMessage {
                Text(unavailableMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let recoveryTitle {
                Button(recoveryTitle, action: onRecovery)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }

            ConversationComposer(
                question: $question,
                isResponding: isResponding,
                isEnabled: canAsk && selectedText != nil,
                pinnedPassage: pinnedPassage,
                onOpenPassage: onOpenPassage,
                onDismissPassage: onDismissPassage,
                onSend: onSend,
                onStop: onStop,
                onModelChange: onModelChange
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    /// A bubble leaves `bubbleHorizontalInset` free on its opposite edge so the
    /// sender is readable at a glance; everything left over after the scroll
    /// view's own 16pt inset each side is the bubble's, which is what long
    /// equations need.
    private var bubbleWidth: CGFloat {
        max(120, panelWidth - 32 - ConversationChrome.bubbleHorizontalInset)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if isResponding {
            if streamingText != nil, !(streamingText?.isEmpty ?? true) {
                // Unanimated: this fires on every coalesced streaming flush, and
                // overlapping 200ms animations churn against each other.
                proxy.scrollTo("streaming", anchor: .bottom)
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("thinking", anchor: .bottom)
                }
            }
        } else if let lastID = messages.last?.id {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }
}

/// Follow-up pills belong to the latest finished answer. Sending another
/// question clears them immediately, before the next answer arrives.
enum ConversationFollowUps {
    static func shouldShow(
        on message: ThreadMessage,
        in messages: [ThreadMessage],
        isResponding: Bool
    ) -> Bool {
        guard !isResponding, message.role == .assistant else { return false }
        guard let last = messages.last, last.role == .assistant, last.id == message.id else { return false }
        return true
    }
}
