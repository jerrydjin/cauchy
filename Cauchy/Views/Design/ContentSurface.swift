import SwiftUI

/// The fill for *content* — message bubbles, reference cards.
///
/// Deliberately not glass. Liquid Glass is the layer that floats *above*
/// content: navigation and controls live there so the content underneath stays
/// the focus. Apple's adoption guidance is to reduce custom backgrounds in that
/// layer precisely because they interfere with the glass and with the scroll
/// edge effect the system draws where content passes beneath a bar — and the
/// corollary is that content itself should not be pretending to be chrome.
///
/// One flat grey, no hairline. A border was only ever needed to keep glass
/// panes from dissolving into each other; a solid fill on a darker backdrop
/// separates on its own. `bubble` is the dark grey. `bubble(for:)` is that
/// grey in dark mode and its light pair otherwise.
enum ContentSurface {
    /// Roughly the grey iMessage gives an incoming bubble in dark mode.
    /// A fixed sRGB, so a dark snapshot stays the colour it was drawn with.
    static let bubble = Color(red: 0.227, green: 0.227, blue: 0.235)

    /// The same bubble in light mode. Slightly under the snapshot window
    /// (`0.94`) so the card still separates from the page behind it.
    static let bubbleLight = Color(red: 233.0 / 255, green: 233.0 / 255, blue: 235.0 / 255)

    static func bubble(for scheme: ColorScheme) -> Color {
        scheme == .dark ? bubble : bubbleLight
    }
}
