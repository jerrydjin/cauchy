import SwiftUI

struct SelectionQuoteView: View {
    let text: String
    var lineLimit: Int? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(CitationChrome.tint)
                .frame(width: 2)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .lineLimit(lineLimit)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

enum PassageChipRole {
    /// Above the composer. Tap jumps to the page. × dismisses.
    case composer
    /// On a sent message. The quote is the chip. No dismiss control.
    case transcript
}

/// The quote, and the blue bar beside it. No page number and no header.
/// Hovering either chip opens the full passage in the answer-card style.
struct PassageChipView: View {
    var passage: PinnedPassage
    var role: PassageChipRole
    /// The designer snapshot paints the hover card in the layout. Live hover
    /// uses a popover, which ImageRenderer does not draw.
    var showsHoverCard = false
    var onOpen: () -> Void
    var onDismiss: () -> Void = {}

    @State private var isHovering = false

    init(
        passage: PinnedPassage,
        role: PassageChipRole,
        showsHoverCard: Bool = false,
        onOpen: @escaping () -> Void,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.passage = passage
        self.role = role
        self.showsHoverCard = showsHoverCard
        self.onOpen = onOpen
        self.onDismiss = onDismiss
    }

    private var quote: String {
        PinnedPassage.singleLine(passage.excerpt)
    }

    private var popoverPresented: Binding<Bool> {
        Binding(
            get: { isHovering && !showsHoverCard },
            set: { presented in
                if !presented { isHovering = false }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ConversationChrome.passageChipComposerSpacing) {
            if showsHoverCard {
                PassageQuoteCard(text: quote)
            }
            chipRow
        }
        .onHover { hovering in
            if isHovering != hovering { isHovering = hovering }
        }
        .popover(isPresented: popoverPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            PassageQuoteCard(text: quote)
                .presentationBackground(ContentSurface.bubble)
        }
    }

    @ViewBuilder
    private var chipRow: some View {
        // The composer chip is one object above the bar: the quote and the
        // dismiss control share a quiet fill. No header, no rule, no page.
        if role == .composer {
            chipContents
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Color.primary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
        } else {
            chipContents
        }
    }

    private var chipContents: some View {
        HStack(alignment: .top, spacing: 8) {
            quoteControl
            if role == .composer {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss passage")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var quoteControl: some View {
        if role == .composer {
            Button(action: onOpen) {
                SelectionQuoteView(text: quote, lineLimit: 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(quote)
            .accessibilityHint("Shows this passage in the PDF")
        } else {
            SelectionQuoteView(text: quote, lineLimit: 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(quote)
        }
    }
}

/// Full passage on hover. Same fill, corner radius, and padding as an answer.
struct PassageQuoteCard: View {
    static let maxWidth: CGFloat = 320

    var text: String

    var body: some View {
        SelectionQuoteView(text: text)
            .padding(.horizontal, ConversationChrome.answerPaddingH)
            .padding(.vertical, ConversationChrome.answerPaddingV)
            .frame(maxWidth: Self.maxWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                ContentSurface.bubble,
                in: RoundedRectangle(cornerRadius: ConversationChrome.bubbleCornerRadius)
            )
    }
}
