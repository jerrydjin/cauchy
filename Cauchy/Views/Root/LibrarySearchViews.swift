import SwiftUI

/// The dashboard's search field. Wide and quiet: it searches everything the
/// reader has ever highlighted, which is a bigger promise than the panel's
/// per-document field and should not look like a filter.
struct LibrarySearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Search highlights and conversations in every document", text: $text)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isFocused)
                .accessibilityLabel("Search all documents")

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .glassEffect(.regular, in: .capsule)
        .overlay {
            if isFocused {
                Capsule().strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

struct LibrarySearchResultRow: View {
    let result: LibrarySearchResult
    var onOpen: () -> Void

    @State private var isHovering = false

    private var documentName: String {
        result.documentURL.deletingPathExtension().lastPathComponent
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 10) {
                HighlightColorDot(color: result.highlight.color)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(result.highlight.displayName)
                            .font(.body.weight(.medium))
                            .lineLimit(1)

                        Text("·")
                            .foregroundStyle(.tertiary)

                        Text(documentName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Text("p. \(result.highlight.pageIndex + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }

                    Text(result.snippet)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(isHovering ? 0.07 : 0))
        }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .accessibilityLabel("\(result.highlight.displayName), in \(documentName), page \(result.highlight.pageIndex + 1)")
        .accessibilityHint("Opens the document at this highlight")
    }
}
