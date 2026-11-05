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
    /// The chip and the hover card share this inset. The quote starts here.
    static let passageChipPadding: CGFloat = 12
    /// Quiet fill behind the chip and the hover card.
    static let passageChipFill = Color.primary.opacity(0.08)
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
