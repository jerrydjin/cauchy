import AppKit
import SwiftUI

struct MessageBubble: View {
    let message: ThreadMessage
    var quotedText: String?
    var maxBubbleWidth: CGFloat = 300
    var onOpenSource: (AnswerSourceAnchor) -> Void = { _ in }

    private var isUser: Bool {
        message.role == .user
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
                        textColor: .primary
                    )
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                MessageContentView(
                    content: message.content,
                    font: .body,
                    textColor: .primary
                )
                if let evidence = message.answerEvidence {
                    Divider().opacity(0.25)
                    Label(
                        "\(evidence.basis.label) · \(evidence.sourcePagesLabel)",
                        systemImage: evidence.basis.systemImage
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help(evidence.auditDescription)
                    .accessibilityLabel("Answer basis: \(evidence.basis.label). Sources supplied: \(evidence.sourcePagesLabel).")
                    .accessibilityHint(evidence.auditDescription)

                    if let status = evidence.citationStatus {
                        Text(status.label)
                            .font(.caption2)
                            .foregroundStyle(status == .idsResolve ? Color.secondary : Color.orange)
                            .help("This checks source IDs and PDF locations, not whether the answer follows from them.")
                    }

                    if let anchors = evidence.sourceAnchors, !anchors.isEmpty {
                        let citedIDs = Set(evidence.citedSourceIDs ?? [])
                        let shown = citedIDs.isEmpty
                            ? anchors
                            : anchors.filter { $0.sourceID.map(citedIDs.contains) == true }
                        DisclosureGroup(citedIDs.isEmpty ? "PDF locations supplied" : "Cited PDF locations") {
                            ForEach(Array(shown.enumerated()), id: \.offset) { _, anchor in
                                Button {
                                    onOpenSource(anchor)
                                } label: {
                                    Label(
                                        "\(anchor.sourceID.map { "[\($0)] " } ?? "")\(anchor.label) · p. \(anchor.pageIndex + 1)",
                                        systemImage: "arrow.up.forward.square"
                                    )
                                }
                                .buttonStyle(.link)
                                .font(.caption)
                                .help("Open the original PDF source. This does not prove the answer's claims.")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
