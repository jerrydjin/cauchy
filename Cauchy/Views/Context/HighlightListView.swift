import AppKit
import SwiftUI

struct HighlightListView: View {
    @Bindable var workspace: WorkspaceViewModel

    private var highlights: [Highlight] {
        workspace.highlightStore.filteredHighlights
    }

    var body: some View {
        VStack(spacing: 0) {
            if !workspace.highlightStore.highlights.isEmpty {
                ThreadSearchField(text: $workspace.highlightStore.searchText)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            if highlights.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(highlights) { highlight in
                            HighlightRow(
                                highlight: highlight,
                                onOpen: { workspace.selectHighlight(highlight) },
                                onRename: { workspace.regenerateThreadTitle(for: highlight) },
                                onDelete: { workspace.deleteHighlight(highlight) }
                            )
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 16)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .animation(.snappy(duration: 0.2), value: highlights.map(\.id))
    }

    @ViewBuilder
    private var emptyState: some View {
        if workspace.highlightStore.searchText.isEmpty {
            ContentUnavailableView(
                "No Highlights Yet",
                systemImage: "highlighter",
                description: Text("Select text in the PDF to start a highlight.")
            )
        } else {
            ContentUnavailableView.search(text: workspace.highlightStore.searchText)
        }
    }
}

/// The panel's search field, on Liquid Glass. `.searchable` puts a system
/// search bar at the top of a List, which brings the List's chrome and its own
/// grey with it.
private struct ThreadSearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search threads", text: $text)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .focused($isFocused)
                .onSubmit { isFocused = false }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        // Glass goes on last, after everything that affects appearance — the
        // modifier captures the content it sits above.
        .glassEffect(.regular, in: .capsule)
        .overlay {
            if isFocused {
                Capsule().strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

/// One thread per row: its name, and the page it lives on. Plain rows rather
/// than cards — a list of twenty glass panes is both noisy and against Apple's
/// advice on how many Liquid Glass effects to put on screen at once. The glass
/// in this panel is reserved for the controls above.
private struct HighlightRow: View {
    let highlight: Highlight
    var onOpen: () -> Void
    var onRename: () -> Void
    var onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Text(highlight.displayName)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                HStack(spacing: 3) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10, weight: .medium))
                    Text("\(highlight.pageIndex + 1)")
                        .font(.caption.monospacedDigit())
                }
                .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(isHovering ? 0.07 : 0))
        }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help(highlight.selectedText)
        .contextMenu {
            Button("Rename with AI", action: onRename)
            Button("Copy Passage") { copyPassage() }
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private func copyPassage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(highlight.selectedText, forType: .string)
    }
}
