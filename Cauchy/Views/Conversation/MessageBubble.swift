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

/// Closed on every new answer. Collapsed it is a quiet bordered pill,
/// "Sources · N pages" with a chevron. Expanded, one line of page tags.
struct CitedSourcesDisclosure: View {
    var pages: [CitedSourcePage]
    var startExpanded: Bool
    var onOpen: (AnswerSourceAnchor) -> Void

    @State private var isExpanded: Bool

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
                    Text(CitedSourceSummary.disclosureLabel(pageCount: pages.count))
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
                        .fill(CitationChrome.tint.opacity(0.06))
                        .overlay {
                            Capsule().strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                        }
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
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
                                .foregroundStyle(.primary)
                                .fixedSize()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var lineTokens: [(title: String, page: CitedSourcePage?)] {
        var tokens: [(title: String, page: CitedSourcePage?)] = []
        for (index, page) in pages.enumerated() {
            if index > 0 {
                tokens.append((", ", nil))
            }
            tokens.append((page.pageLabel, page))
        }
        return tokens
    }
}
