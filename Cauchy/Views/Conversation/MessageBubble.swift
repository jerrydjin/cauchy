import SwiftUI

struct MessageBubble: View {
    let message: ThreadMessage
    var quotedText: String?
    var maxBubbleWidth: CGFloat = 300

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: ConversationChrome.bubbleHorizontalInset) }

            bubbleContent
                .padding(.horizontal, ConversationChrome.bubbleContentPaddingH)
                .padding(.vertical, ConversationChrome.bubbleContentPaddingV)
                .glassEffect(
                    isUser ? .regular.tint(.accentColor) : .regular,
                    in: .rect(cornerRadius: ConversationChrome.bubbleCornerRadius)
                )
                .frame(maxWidth: maxBubbleWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if !isUser { Spacer(minLength: ConversationChrome.bubbleHorizontalInset) }
        }
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
                        textColor: .primary
                    )
                }
            }
        } else {
            MessageContentView(
                content: message.content,
                font: .body,
                textColor: .primary
            )
        }
    }
}
