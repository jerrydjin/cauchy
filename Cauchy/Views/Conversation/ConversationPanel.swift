import SwiftUI

/// The conversation, with its chrome floating over it.
///
/// The header and the composer are `safeAreaBar`s rather than rows stacked
/// above and below a shorter scroll view. That is the arrangement Apple's
/// adoption guidance describes for a custom bar: the messages run the full
/// height and pass *beneath* the glass, and the scroll view's edge effect
/// blurs whatever is under a bar so its controls stay legible. Stacking
/// instead gives a hard cut where the content simply stops, which is the one
/// thing the glass layer is meant not to do.
///
/// The bars still reserve their own height in the safe area, so the first and
/// last message can always be scrolled clear of them.
struct ConversationPanel<Header: View>: View {
    let selectedText: String?
    let messages: [ThreadMessage]
    var streamingText: String?
    var isResponding: Bool
    var isAskAvailable: Bool
    var unavailabilityMessage: String?
    var panelWidth: CGFloat
    @Binding var question: String
    var onSend: () -> Void
    var onStop: () -> Void = {}
    var onModelChange: () -> Void = {}
    @ViewBuilder var header: Header

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if let selectedText, !selectedText.isEmpty {
                        MessageBubble(
                            message: ThreadMessage(role: .user, content: ""),
                            quotedText: selectedText,
                            maxBubbleWidth: bubbleWidth
                        )
                        .id("quote-only")
                    }

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
                            maxBubbleWidth: bubbleWidth
                        )
                        .id(message.id)
                    }

                    if isResponding, let streamingText, !streamingText.isEmpty {
                        MessageBubble(
                            message: ThreadMessage(role: .assistant, content: streamingText),
                            maxBubbleWidth: bubbleWidth
                        )
                        .id("streaming")
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
            .safeAreaBar(edge: .top) { header }
            .safeAreaBar(edge: .bottom) { composerBar }
            // `.hard` at the top because the header carries a title that has to
            // stay readable over whatever passes under it — an accent-coloured
            // quote bubble, most often. The composer is glass and does its own
            // obscuring, so the bottom only needs the gentle fade.
            .scrollEdgeEffectStyle(.hard, for: .top)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .onAppear {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: streamingText) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private var composerBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !isAskAvailable, let unavailabilityMessage {
                Text(unavailabilityMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ConversationComposer(
                question: $question,
                isResponding: isResponding,
                isEnabled: isAskAvailable && selectedText != nil,
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
        max(280, panelWidth - 32 - ConversationChrome.bubbleHorizontalInset)
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
