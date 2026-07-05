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

private struct HighlightListRow: View {
    let highlight: Highlight

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(highlight.label)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                Text(highlight.selectedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text("Page \(highlight.pageIndex + 1)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            if !highlight.messages.isEmpty {
                Text("\(highlight.messages.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}
