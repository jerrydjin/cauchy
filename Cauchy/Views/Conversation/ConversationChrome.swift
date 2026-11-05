import AppKit
import SwiftUI

enum ConversationChrome {
    static let bubbleCornerRadius: CGFloat = 18
    static let composerCornerRadius: CGFloat = 20
    static let bubbleHorizontalInset: CGFloat = 12
    /// User bubble and the failure note. The answer bubble uses the values below.
    static let bubbleContentPaddingH: CGFloat = 14
    static let bubbleContentPaddingV: CGFloat = 10
    /// Space between the passage chip and the composer bar. 8pt, on the 4-point scale.
    static let passageChipComposerSpacing: CGFloat = 8
    /// The jump button sits this far above the chip, or above the composer when there is no chip.
    static let jumpButtonGap: CGFloat = 8
    /// Round jump button. About 28pt across, the chevron alone inside it.
    static let jumpButtonDiameter: CGFloat = 28
    /// The chip and the hover card share this inset. The quote starts here.
    static let passageChipPadding: CGFloat = 12
    /// Wash over the opaque panel colour. The chip composites this onto
    /// `headerBackdrop`, so the card is solid and the transcript cannot show through.
    static let passageChipWash = Color.primary.opacity(0.08)
    /// Same colour as the panel. The header has to be opaque: the subtitle is
    /// secondary, and a clear bar leaves the line scrolling underneath readable.
    static let headerBackdrop = Color(nsColor: .windowBackgroundColor)

    /// Answer-area spacing. Every value is on a 4-point scale.
    static let answerPaddingH: CGFloat = 20
    static let answerPaddingV: CGFloat = 16
    /// From an answer's last line to the block under it. Kept on the 4-point scale.
    static let answerSourcesGap: CGFloat = 12
    /// From the answer bubble to the first follow-up pill.
    static let answerFollowUpGap: CGFloat = 16
    /// Between follow-up pills.
    static let answerFollowUpSpacing: CGFloat = 8
    static let answerFollowUpPaddingH: CGFloat = 14
    static let answerFollowUpPaddingV: CGFloat = 8
    /// Kept on the 4-point scale. Follow-up pills no longer show a page mark.
    static let answerFollowUpPageGap: CGFloat = 12
}

/// Solid chip and hover card. The panel colour is opaque; the wash only
/// tints it. A translucent fill let the transcript show through the quote.
struct PassageChipBackground: View {
    var cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(ConversationChrome.headerBackdrop)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(ConversationChrome.passageChipWash)
            }
    }
}

/// Round control that jumps back to the latest message. Liquid Glass, no
/// custom fill and no hairline. The accessibility name stays "Jump to latest".
struct JumpToLatestButton: View {
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(
                    width: ConversationChrome.jumpButtonDiameter,
                    height: ConversationChrome.jumpButtonDiameter
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .modifier(JumpButtonGlass())
        .accessibilityLabel("Jump to latest")
    }
}

/// Regular interactive glass in a circle. The snapshot tool still builds
/// for macOS 14, where `glassEffect` does not exist; the live app is macOS 27.
private struct JumpButtonGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
        }
    }
}
