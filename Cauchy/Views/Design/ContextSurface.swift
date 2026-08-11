import SwiftUI

/// One dark palette for the context panel.
///
/// The panel used to be built entirely from `glassEffect` and
/// `.ultraThinMaterial`. Both sample whatever sits behind them, and behind this
/// panel is a cream PDF page — so the tab picker, the back button, the answer
/// bubbles, the reference card and the composer each landed on a slightly
/// different warm grey, and all of them drifted as the reader scrolled. These
/// are fixed colours: the panel reads as one surface whatever the document
/// looks like.
///
/// Glass is still right *over* the page — the toolbar and the find bar keep it.
/// This palette is only for chrome that sits inside the panel.
/// The panel deliberately has no background of its own: it lets the reader's
/// backdrop run straight through, so the only edge between page and panel is
/// the resize grip. Giving the panel its own dark turned that grip into a grey
/// stripe down the window.
enum ContextSurface {
    /// Anything raised off the panel: cards, bubbles, the composer, the tab
    /// picker's track. Lighter than the backdrop it sits on.
    static let raised = Color(red: 0.215, green: 0.215, blue: 0.225)

    /// A selected control sitting on `raised` — one step lighter, so the two
    /// separate without a second hue entering the panel.
    static let raisedSelected = Color(red: 0.29, green: 0.29, blue: 0.305)

    /// Hairline shared by every raised surface. Glass came with an edge; flat
    /// fills need one drawn, or cards dissolve into the background.
    static let border = Color.white.opacity(0.08)
}

extension View {
    /// The panel's standard raised surface: flat fill plus hairline.
    func contextSurface(
        _ fill: Color = ContextSurface.raised,
        in shape: some InsettableShape
    ) -> some View {
        background(fill, in: shape)
            .overlay { shape.strokeBorder(ContextSurface.border, lineWidth: 1) }
    }
}
