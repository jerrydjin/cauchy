import SwiftUI

/// The colour choices for one highlight. Used from both the panel list and the
/// thread header so the two never drift apart.
///
/// A palette picker rather than a submenu of buttons: a menu item's `Image` is
/// drawn as a template, so a row of SF Symbol swatches all come out the same
/// grey — a colour picker showing no colours. A palette picker tints each
/// symbol with the item's own `tint`, which is the whole point of the control.
struct HighlightColorMenu: View {
    let current: HighlightColor
    var onSelect: (HighlightColor) -> Void

    var body: some View {
        Picker("Colour", selection: selection) {
            ForEach(HighlightColor.allCases) { color in
                Label(color.displayName, systemImage: "largecircle.fill.circle")
                    .tint(color.swiftUIColor)
                    .tag(color)
            }
        }
        .pickerStyle(.palette)
    }

    private var selection: Binding<HighlightColor> {
        Binding(get: { current }, set: { onSelect($0) })
    }
}

/// The small colour dot a highlight is filed under.
struct HighlightColorDot: View {
    let color: HighlightColor
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color.swiftUIColor)
            .frame(width: size, height: size)
            .overlay {
                Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}
