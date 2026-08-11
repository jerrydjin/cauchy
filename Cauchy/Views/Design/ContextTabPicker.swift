import SwiftUI

/// Highlights / Reference: a full-width Liquid Glass switcher.
///
/// The pill is its own layer sitting behind the labels, positioned by an
/// offset, rather than a glass effect attached to whichever label is selected.
/// That is the difference between a switcher that *tracks* a drag and one that
/// teleports: with the pill on the label, the best it can do is jump a whole
/// segment at a time as the cursor crosses a boundary. Here it follows the
/// cursor point for point and springs to the nearest segment on release.
///
/// Why this is hand-rolled at all: a segmented `Picker` pins its segments to
/// their intrinsic width — it will not fill the panel whatever frame it is
/// given — and it only draws the glass pill on a glass backdrop (a toolbar, or
/// an explicit `.glassEffect`), which then reads as a second shell around the
/// control. Both measured on macOS 26.
///
/// The exact iMessage-style morph is not reachable from public API; it comes
/// from a private framework available only to system controls. This is the
/// close approximation the public API allows.
struct ContextTabPicker<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]

    /// Width of the strip the pill travels along — the control minus its
    /// padding. Zero until first layout, which the offset maths guards against.
    @State private var innerWidth: CGFloat = 0
    /// Live cursor displacement, non-nil only while a drag is in flight.
    @State private var dragTranslation: CGFloat?
    @GestureState private var isPressed = false

    private let trackPadding: CGFloat = 3
    /// Marks how far the control extends without putting a second pane behind
    /// the pill — glass inside glass is what Apple's guidance warns against.
    private let trackHairline = Color.white.opacity(0.08)

    private var segmentCount: Int { max(options.count, 1) }
    private var segmentWidth: CGFloat { max(innerWidth / CGFloat(segmentCount), 1) }
    private var selectedIndex: Int {
        options.firstIndex { $0.0 == selection } ?? 0
    }

    /// Where the pill sits: its segment's home, plus however far the cursor has
    /// dragged it, clamped to the ends of the track.
    private var indicatorOffset: CGFloat {
        let home = CGFloat(selectedIndex) * segmentWidth
        guard let dragTranslation else { return home }
        let limit = CGFloat(segmentCount - 1) * segmentWidth
        return min(max(home + dragTranslation, 0), limit)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                label(for: option, isSelected: index == selectedIndex)
            }
        }
        // The pill lives in the labels' background, not in a ZStack beside
        // them: a background is offered exactly the primary view's size, so it
        // inherits the row's height. Asking for `maxHeight: .infinity` in a
        // ZStack instead makes the whole control greedy and it swallows the
        // panel.
        .background(alignment: .leading) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: .capsule)
                .frame(width: segmentWidth)
                // Scale rather than a wider frame, so the pill swells over its
                // neighbours instead of shoving them sideways mid-drag.
                // `.interactive()` alone does not do this on macOS.
                .scaleEffect(isPressed ? 1.06 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.72), value: isPressed)
                .offset(x: indicatorOffset)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { innerWidth = $0 }
        .contentShape(Capsule())
        .gesture(drag)
        .padding(trackPadding)
        .background {
            Capsule().strokeBorder(trackHairline, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private func label(for option: (T, String), isSelected: Bool) -> some View {
        Text(option.1)
            .font(.subheadline.weight(isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .accessibilityLabel(option.1)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { select(option.0, animated: true) }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isPressed) { _, pressed, _ in pressed = true }
            .onChanged { value in
                // Pressing an unselected segment takes the selection there
                // first, so the drag continues from under the cursor rather
                // than dragging the pill in from wherever it used to be.
                if dragTranslation == nil {
                    select(options[index(atX: value.startLocation.x)].0, animated: true)
                }
                // Unanimated: this must be one-to-one with the cursor.
                dragTranslation = value.translation.width
            }
            .onEnded { _ in
                let nearest = Int((indicatorOffset / segmentWidth).rounded())
                let clamped = min(max(nearest, 0), segmentCount - 1)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    dragTranslation = nil
                    selection = options[clamped].0
                }
            }
    }

    private func index(atX x: CGFloat) -> Int {
        let index = Int(x / segmentWidth)
        return min(max(index, 0), segmentCount - 1)
    }

    private func select(_ value: T, animated: Bool) {
        guard value != selection else { return }
        if animated {
            withAnimation(.smooth(duration: 0.2)) { selection = value }
        } else {
            selection = value
        }
    }
}
