import SwiftUI

struct ConversationPanel: View {
    let selectedText: String?
    let messages: [ThreadMessage]
    var streamingText: String?
    var isResponding: Bool
    var isAskAvailable: Bool
    var unavailabilityMessage: String?
    var panelWidth: CGFloat
    @Binding var question: String
    var onSend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 180, maxHeight: .infinity)
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

            if !isAskAvailable, let unavailabilityMessage {
                Text(unavailabilityMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ConversationComposer(
                question: $question,
                isResponding: isResponding,
                isEnabled: isAskAvailable && selectedText != nil,
                onSend: onSend
            )
        }
    }

    private var bubbleWidth: CGFloat {
        max(220, panelWidth - 80)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if isResponding {
                if streamingText != nil, !(streamingText?.isEmpty ?? true) {
                    proxy.scrollTo("streaming", anchor: .bottom)
                } else {
                    proxy.scrollTo("thinking", anchor: .bottom)
                }
            } else if let lastID = messages.last?.id {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }
}
