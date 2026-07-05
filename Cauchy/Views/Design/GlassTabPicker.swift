import SwiftUI

struct GlassTabPicker<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]

    @Namespace private var namespace

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 2) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    tabButton(value: option.0, title: option.1)
                }
            }
            .padding(3)
            .glassEffect(in: .capsule)
        }
    }

    private func tabButton(value: T, title: String) -> some View {
        let isSelected = selection == value

        return Button {
            withAnimation(.snappy(duration: 0.25)) {
                selection = value
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .padding(.horizontal, 10)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                Capsule()
                    .fill(.clear)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .glassEffectID("selectedTab", in: namespace)
            }
        }
    }
}
