import SwiftUI

struct FindBarView: View {
    @Bindable var find: PDFFindModel
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Find in document", text: $find.query)
                .textFieldStyle(.plain)
                .frame(width: 200)
                .focused($isFieldFocused)
                .onSubmit { find.findNext() }

            if !find.query.isEmpty {
                Text(matchLabel)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }

            Divider()
                .frame(height: 16)

            GlassIconButton(systemName: "chevron.up", accessibilityLabel: "Previous Match") {
                find.findPrevious()
            }
            .disabled(!find.hasMatches)

            GlassIconButton(systemName: "chevron.down", accessibilityLabel: "Next Match") {
                find.findNext()
            }
            .disabled(!find.hasMatches)

            GlassIconButton(systemName: "xmark", accessibilityLabel: "Close Find Bar") {
                find.dismiss()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(in: .capsule)
        .onExitCommand { find.dismiss() }
        .onAppear { isFieldFocused = true }
        .onChange(of: find.focusRequest) {
            isFieldFocused = true
        }
    }

    private var matchLabel: String {
        guard find.hasMatches else { return "Not found" }
        let position = (find.currentIndex ?? 0) + 1
        return "\(position) of \(find.matches.count)"
    }
}
