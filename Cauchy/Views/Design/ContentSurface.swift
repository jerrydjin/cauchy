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
/// separates on its own.
enum ContentSurface {
    /// Roughly the grey iMessage gives an incoming bubble in dark mode.
    static let bubble = Color(red: 0.227, green: 0.227, blue: 0.235)
}
