import SwiftUI

/// A full-width view switcher with one moving Liquid Glass capsule.
/// Preserve the reader's glass design while exposing a native segmented
/// picker's selection semantics to assistive technology.
struct ContextTabPicker<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var innerWidth: CGFloat = 0
    @State private var dragTranslation: CGFloat?
    @FocusState private var isFocused: Bool

    private let trackPadding: CGFloat = 3
    private var segmentCount: Int { max(options.count, 1) }
    private var segmentWidth: CGFloat { max(innerWidth / CGFloat(segmentCount), 1) }
    private var selectedIndex: Int { options.firstIndex { $0.0 == selection } ?? 0 }

    private var indicatorOffset: CGFloat {
        let home = CGFloat(selectedIndex) * segmentWidth
        return min(max(home + (dragTranslation ?? 0), 0), CGFloat(segmentCount - 1) * segmentWidth)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Text(option.1)
                    .font(.subheadline.weight(index == selectedIndex ? .semibold : .medium))
                    .foregroundStyle(index == selectedIndex ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
            }
        }
        .background(alignment: .leading) {
            if !options.isEmpty {
                Capsule()
                    .fill(.clear)
                    .frame(width: segmentWidth)
                    // macOS 27 supplies pointer-responsive glass. No simulated
                    // press scaling or second glass surface around the track.
                    .glassEffect(.regular.interactive(!reduceMotion), in: .capsule)
                    .offset(x: indicatorOffset)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { innerWidth = $0 }
        .contentShape(Capsule())
        .gesture(drag)
        .padding(trackPadding)
        .background {
            Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .focusable(!options.isEmpty, interactions: .edit)
        .focused($isFocused)
        .onKeyPress(keys: [.leftArrow, .rightArrow], phases: .down) { key in
            // Arrow events may carry the system's function-key flag. Only
            // intentional shortcut modifiers should bypass view switching.
            guard key.modifiers.intersection([.command, .control, .option, .shift]).isEmpty,
                  !options.isEmpty else { return .ignored }
            let delta = key.key == .rightArrow ? 1 : -1
            let index = min(max(selectedIndex + delta, 0), options.count - 1)
            select(options[index].0)
            return .handled
        }
        .accessibilityRepresentation {
            Picker("Context", selection: Binding(get: { selection }, set: { value in
                select(value)
                isFocused = true
            })) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Text(option.1).tag(option.0)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !options.isEmpty else { return }
                isFocused = true
                if dragTranslation == nil {
                    let index = min(max(Int(value.startLocation.x / segmentWidth), 0), options.count - 1)
                    select(options[index].0)
                }
                // Direct manipulation follows the pointer without an animation.
                dragTranslation = value.translation.width
            }
            .onEnded { _ in
                guard !options.isEmpty else { return }
                let nearest = Int((indicatorOffset / segmentWidth).rounded())
                let index = min(max(nearest, 0), options.count - 1)
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                    dragTranslation = nil
                    selection = options[index].0
                }
            }
    }

    private func select(_ value: T) {
        guard value != selection else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) {
            selection = value
        }
    }
}
