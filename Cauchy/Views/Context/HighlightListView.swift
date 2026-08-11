import SwiftUI

struct HighlightListView: View {
    @Bindable var workspace: WorkspaceViewModel

    var body: some View {
        List {
            if workspace.highlightStore.filteredHighlights.isEmpty {
                ContentUnavailableView(
                    "No Highlights Yet",
                    systemImage: "highlighter",
                    description: Text("Select text in the PDF to start a highlight.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(workspace.highlightStore.filteredHighlights) { highlight in
                    HighlightListRow(highlight: highlight)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            workspace.selectHighlight(highlight)
                        }
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                workspace.deleteHighlight(highlight)
                            }
                        }
                }
            }
        }
        .listStyle(.plain)
        .searchable(
            text: $workspace.highlightStore.searchText,
            prompt: "Search highlights"
        )
    }
}

/// One line per thread: what it is called, how long it is, where it lives. The
/// passage itself is not repeated here — the row's name is drawn from it, and
/// the highlight is one tap away.
private struct HighlightListRow: View {
    let highlight: Highlight

    var body: some View {
        HStack(spacing: 8) {
            Text(highlight.displayName)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6)

            if !highlight.messages.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 8))
                    Text("\(highlight.messages.count)")
                        .font(.caption2.weight(.medium).monospacedDigit())
                }
                .foregroundStyle(.secondary)
            }

            Text("p. \(highlight.pageIndex + 1)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .help(highlight.selectedText)
    }
}
