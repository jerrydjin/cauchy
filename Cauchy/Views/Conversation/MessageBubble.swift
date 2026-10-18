import AppKit
import SwiftUI

struct MessageBubble: View {
    let message: ThreadMessage
    var quotedText: String?
    var maxBubbleWidth: CGFloat = 300
    var onOpenSource: (AnswerSourceAnchor) -> Void = { _ in }
    var referenceKeys: Set<ReferenceKey> = []
    var referenceBlock: (DetectedReference) -> DocumentBlock? = { _ in nil }
    var onOpenReference: (DetectedReference) -> Void = { _ in }
    var onHoverReference: (DetectedReference) -> Void = { _ in }

    private var isUser: Bool {
        message.role == .user
    }

    /// Hidden when the answer was not found, so a miss is one plain line.
    private var citationAnchors: [AnswerSourceAnchor] {
        guard message.answerEvidence?.basis != .insufficient else { return [] }
        let anchors = message.answerEvidence?.sourceAnchors ?? []
        return anchors.sorted { lhs, rhs in
            if lhs.pageIndex != rhs.pageIndex { return lhs.pageIndex < rhs.pageIndex }
            return lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
        }
    }

    var body: some View {
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
                        referenceBlock: referenceBlock,
                        onOpenReference: onOpenReference,
                        onHoverReference: onHoverReference
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
                    referenceBlock: referenceBlock,
                    onOpenReference: onOpenReference,
                    onHoverReference: onHoverReference,
                    interpretsSourceMarkers: !isUser,
                    sourceAnchors: citationAnchors,
                    onOpenSource: onOpenSource
                )
                if !citationAnchors.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sources")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        ForEach(Array(citationAnchors.enumerated()), id: \.offset) { _, anchor in
                            Button {
                                onOpenSource(anchor)
                            } label: {
                                Text("\(anchor.label) · p. \(anchor.pageIndex + 1)")
                                    .font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                            .help("Open this in the PDF")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
