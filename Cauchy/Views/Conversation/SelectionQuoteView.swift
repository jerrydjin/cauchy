import SwiftUI

struct SelectionQuoteView: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.accentColor.opacity(0.45))
                .frame(width: 2)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

enum PassageChipRole {
    /// Above the composer. Tap jumps to the page. × dismisses.
    case composer
    /// On a sent message. Tap expands the excerpt. No dismiss control.
    case transcript
}

/// One quiet line: `✎ p. 39 · By taking complements… ×`.
/// The pencil and the `p. N · excerpt` line are the Learning-branch tag.
struct PassageChipView: View {
    var passage: PinnedPassage
    var role: PassageChipRole
    var startsExpanded = false
    var onOpen: () -> Void
    var onDismiss: () -> Void = {}

    @State private var expanded: Bool

    init(
        passage: PinnedPassage,
        role: PassageChipRole,
        startsExpanded: Bool = false,
        onOpen: @escaping () -> Void,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.passage = passage
        self.role = role
        self.startsExpanded = startsExpanded
        self.onOpen = onOpen
        self.onDismiss = onDismiss
        _expanded = State(initialValue: startsExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button(action: activate) {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .semibold))
                            .accessibilityHidden(true)
                        Text(passage.line)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(accessibilityTitle)
                .accessibilityHint(role == .composer ? "Shows this passage in the PDF" : "Shows the full passage")

                if role == .composer {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .padding(4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss passage")
                }
            }

            if role == .transcript, expanded {
                SelectionQuoteView(text: passage.excerpt)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var accessibilityTitle: String {
        "Page \(passage.pageIndex + 1), \(PinnedPassage.singleLine(passage.excerpt))"
    }

    private func activate() {
        switch role {
        case .composer:
            onOpen()
        case .transcript:
            expanded.toggle()
        }
    }
}
