import SwiftUI

struct HighlightsAndNotesSidebarView: View {
    @Bindable var workspace: WorkspaceViewModel

    var body: some View {
        List(selection: $workspace.highlightStore.selectedHighlightID) {
            Section("Highlights") {
                if workspace.highlightStore.filteredHighlights.isEmpty {
                    ContentUnavailableView(
                        "No Highlights Yet",
                        systemImage: "highlighter",
                        description: Text("Select text and tap “Save as highlight”, or use Select Region (⌘⇧S) for figures.")
                    )
                } else {
                    ForEach(workspace.highlightStore.filteredHighlights) { highlight in
                        HighlightRowView(
                            highlight: highlight,
                            isSelected: workspace.highlightStore.selectedHighlightID == highlight.id,
                            onSelect: {
                                workspace.selectHighlight(highlight)
                            },
                            onNavigate: {
                                workspace.navigateToHighlight(highlight)
                            },
                            onDelete: {
                                workspace.deleteHighlight(highlight)
                            }
                        )
                        .tag(highlight.id)
                    }
                }
            }
        }
        .searchable(
            text: $workspace.highlightStore.searchText,
            prompt: "Search highlights"
        )
    }
}
