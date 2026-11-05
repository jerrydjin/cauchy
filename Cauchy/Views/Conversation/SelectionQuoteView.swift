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
struct SentPassageFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct PassageChipView: View {
    var passage: PinnedPassage
    var role: PassageChipRole
    /// The sent quote shares the user bubble's maximum width. Nil on the
    /// composer chip, which is as wide as the composer.
    var maxWidth: CGFloat? = nil
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
        maxWidth: CGFloat? = nil,
        showsHoverCard: Bool = false,
        showsFloatingHoverCard: Bool = false,
        onOpen: @escaping () -> Void,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.passage = passage
        self.role = role
        self.maxWidth = maxWidth
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

    /// Sent passages use the bubble's maximum width. A missing value still
    /// has to wrap; the composer chip is the one that takes the spare width.
    private var sentMaxWidth: CGFloat {
        maxWidth ?? 300
    }

    var body: some View {
        // The card is in the stack, above the chip, with the same gap the
        // chip uses. An overlay aligned by a guide stayed on the chip: the
        // card and the quote drew as one shape, and the old popover's arrow
        // had been a bar above that. Hovering the card does not dismiss it,
        // because the card is inside this view.
        VStack(alignment: role == .transcript ? .trailing : .leading, spacing: ConversationChrome.passageChipComposerSpacing) {
            if showsCard {
                PassageQuoteCard(
                    text: passage.excerpt,
                    maxWidth: role == .transcript ? sentMaxWidth : PassageQuoteCard.maxWidth
                )
                .background { sentFrame("card") }
            }
            chipRow
                .background { sentFrame("quote") }
        }
        // Hug the quote. A parent that proposes the panel's spare height
        // must not stretch the card. The composer chip takes the spare width.
        // A sent quote stays on the bubble's trailing edge and no wider than
        // that bubble's maximum.
        .fixedSize(horizontal: false, vertical: true)
        .frame(
            maxWidth: role == .transcript ? sentMaxWidth : .infinity,
            alignment: role == .transcript ? .trailing : .topLeading
        )
        .onHover { hovering in
            if isHovering != hovering { isHovering = hovering }
        }
    }

    @ViewBuilder
    private func sentFrame(_ name: String) -> some View {
        if role == .transcript {
            GeometryReader { geo in
                Color.clear.preference(
                    key: SentPassageFrameKey.self,
                    value: [name: geo.frame(in: .named("sent-passage"))]
                )
            }
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
        .frame(
            maxWidth: role == .transcript ? sentMaxWidth : .infinity,
            alignment: role == .transcript ? .trailing : .leading
        )
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
                .frame(maxWidth: sentMaxWidth, alignment: .leading)
                .accessibilityLabel(quote)
        }
    }
}

/// Full passage on hover. Same fill as the chip, primary text, no bar.
struct PassageQuoteCard: View {
    static let maxWidth: CGFloat = 320

    var text: String
    var maxWidth: CGFloat = PassageQuoteCard.maxWidth

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(ConversationChrome.passageChipPadding)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .background {
                PassageChipBackground(cornerRadius: ConversationChrome.bubbleCornerRadius)
            }
    }
}
