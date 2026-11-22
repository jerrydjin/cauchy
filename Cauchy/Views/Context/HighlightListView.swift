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
                            HighlightThreadRow(
                                highlight: highlight,
                                isAnswering: workspace.answeringHighlightID == highlight.id,
                                onOpen: { workspace.selectHighlight(highlight) },
                                onRetry: { workspace.retryHighlight(highlight) },
                                onRename: { workspace.regenerateThreadTitle(for: highlight) },
                                onRecolour: { workspace.setColor($0, for: highlight.id) },
                                onCopyMarkdown: { workspace.copyThreadAsMarkdown(highlight) },
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
