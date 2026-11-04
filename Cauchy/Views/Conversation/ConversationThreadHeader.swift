import SwiftUI

/// The chat's title and page. The backdrop is the panel colour, full width,
/// so a line scrolling underneath cannot show through the subtitle.
struct ConversationThreadHeader<Trailing: View>: View {
    var title: String
    var pageNumber: Int?
    var onBack: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            GlassIconButton(
                systemName: "chevron.left",
                accessibilityLabel: "Back",
                action: onBack
            )

            // The thread's name, the same one the list shows.
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let pageNumber {
                    Text("Page \(pageNumber)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            // A label, not a control. Without this the row's empty space is
            // still a hit target and the header behaves like one wide button.
            .allowsHitTesting(false)

            Spacer(minLength: 6)

            trailing
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ConversationChrome.headerBackdrop)
    }
}
