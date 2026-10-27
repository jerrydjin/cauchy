import SwiftUI

/// Insets for one block in the reference card. The statement column and a
/// figure block both use this, and the designer snapshot renders the column.
enum ReferencePreviewBlockChrome {
    static func padded<Content: View>(_ content: Content) -> some View {
        content
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Secondary heading on the reference card. Kind and number, plus a
/// parenthetical name only when that name is not a repeat of the label.
struct ReferencePreviewHeading: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Typeset statement for one reference. The card scrolls this. The designer
/// snapshot renders it directly, because ImageRenderer skips a ScrollView.
struct ReferencePreviewStatementColumn: View {
    let heading: String
    let statement: String

    var body: some View {
        ReferencePreviewBlockChrome.padded(
            VStack(alignment: .leading, spacing: 14) {
                ReferencePreviewHeading(text: heading)
                ReadingBlockCard(displayBody: statement)
            }
        )
    }
}

/// Citation hover for a string that contains math. Plain bibliography stays
/// on the system tooltip; this is the same statement renderer as the card,
/// so inline and display math are not drawn as source text.
struct ReferenceHoverLabel: View {
    var text: String
    var width: CGFloat = 420

    var body: some View {
        MessageContentView(content: text, font: .callout, allowsMonospace: false)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: width, alignment: .leading)
    }
}

/// "Source", collapsed until the reader opens the verbatim page text.
struct ReferencePreviewSourceDisclosure<Content: View>: View {
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            DisclosureGroup(isExpanded: $isExpanded) {
                content()
            } label: {
                Text("Source")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }
}
