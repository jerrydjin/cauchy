import SwiftUI

struct SelectionQuoteView: View {
    let text: String
    var lineLimit: Int? = nil

    var body: some View {
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

enum PassageChipRole {
    /// Above the composer. Tap jumps to the page. × dismisses.
    case composer
    /// On a sent message. The quote is the chip. No dismiss control.
    case transcript
}

/// The quote. No page number, no icon, no rule. Hovering either chip opens
/// the full passage as the same card, in the stack above the chip. There is
/// no popover: the system popover drew an arrow and a second plate, and that
/// arrow landed as a thin bar above the card whenever the anchor flipped.
struct PassageChipView: View {
    var passage: PinnedPassage
    var role: PassageChipRole
    /// The designer snapshot paints the card in the stack above the chip.
    var showsHoverCard = false
    /// Snapshot of the hover. The card is the same stack as `showsHoverCard`.
    var showsFloatingHoverCard = false
    var onOpen: () -> Void
    var onDismiss: () -> Void = {}

    @State private var isHovering = false

    init(
        passage: PinnedPassage,
        role: PassageChipRole,
        showsHoverCard: Bool = false,
        showsFloatingHoverCard: Bool = false,
        onOpen: @escaping () -> Void,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.passage = passage
        self.role = role
        self.showsHoverCard = showsHoverCard
        self.showsFloatingHoverCard = showsFloatingHoverCard
        self.onOpen = onOpen
        self.onDismiss = onDismiss
    }

    private var quote: String {
        PinnedPassage.singleLine(passage.excerpt)
    }

    private var showsCard: Bool {
        showsHoverCard || showsFloatingHoverCard || isHovering
    }

    var body: some View {
        // The card is in the stack, above the chip, with the same gap the
        // chip uses. An overlay aligned by a guide stayed on the chip: the
        // card and the quote drew as one shape, and the old popover's arrow
        // had been a bar above that. Hovering the card does not dismiss it,
        // because the card is inside this view.
        VStack(alignment: .leading, spacing: ConversationChrome.passageChipComposerSpacing) {
            if showsCard {
                PassageQuoteCard(text: passage.excerpt)
            }
            chipRow
        }
        // Hug the quote. A parent that proposes the panel's spare height
        // must not stretch the card. The frame keeps the card as wide as the composer.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onHover { hovering in
            if isHovering != hovering { isHovering = hovering }
        }
    }

    @ViewBuilder
    private var chipRow: some View {
        // The composer chip is one object above the bar: the quote and the
        // dismiss control share a quiet fill. No header, no rule, no page.
        if role == .composer {
            chipContents
                .padding(ConversationChrome.passageChipPadding)
                .background { PassageChipBackground(cornerRadius: 14) }
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

/// Full passage on hover. Same fill as the chip, primary text, no bar.
struct PassageQuoteCard: View {
    static let maxWidth: CGFloat = 320

    var text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(ConversationChrome.passageChipPadding)
            .frame(maxWidth: Self.maxWidth, alignment: .leading)
            .background {
                PassageChipBackground(cornerRadius: ConversationChrome.bubbleCornerRadius)
            }
    }
}
