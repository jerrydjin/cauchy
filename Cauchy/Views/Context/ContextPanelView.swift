import SwiftUI

struct ContextPanelView: View {
    @Bindable var workspace: WorkspaceViewModel

    var body: some View {
        VStack(spacing: 0) {
            GlassTabPicker(
                selection: $workspace.contextEngine.selectedTab,
                options: [
                    (.highlights, "Highlights"),
                    (.reference, "Reference"),
                ]
            )
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Group {
                switch workspace.contextEngine.selectedTab {
                case .highlights:
                    highlightsContent
                case .reference:
                    ReferencePreviewView(workspace: workspace)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var highlightsContent: some View {
        switch workspace.contextEngine.route {
        case .list:
            HighlightListView(workspace: workspace)
        case .detail(let id):
            if let highlight = workspace.highlightStore.highlights.first(where: { $0.id == id }) {
                HighlightThreadDetailView(
                    workspace: workspace,
                    onBack: { workspace.showHighlightList() }
                )
            } else {
                HighlightListView(workspace: workspace)
                    .onAppear { workspace.showHighlightList() }
            }
        case .composeDraft:
            HighlightThreadDetailView(
                workspace: workspace,
                onBack: { workspace.showHighlightList() }
            )
        }
    }
}
