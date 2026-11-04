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

    /// Answer-area spacing. Every value is on a 4-point scale.
    static let answerPaddingH: CGFloat = 20
    static let answerPaddingV: CGFloat = 16
    /// From the answer's last line to the Sources pill.
    static let answerSourcesGap: CGFloat = 12
    /// From the answer bubble to the first follow-up pill.
    static let answerFollowUpGap: CGFloat = 16
    /// Between follow-up pills.
    static let answerFollowUpSpacing: CGFloat = 8
    static let answerFollowUpPaddingH: CGFloat = 14
    static let answerFollowUpPaddingV: CGFloat = 8
    /// Between a follow-up's question and its page mark.
    static let answerFollowUpPageGap: CGFloat = 12
}
