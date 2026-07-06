import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var workspace: WorkspaceViewModel

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { workspace.sidebarVisible ? .all : .detailOnly },
            set: { workspace.sidebarVisible = $0 != .detailOnly }
        )
    }

    var body: some View {
        Group {
            if workspace.pdfDocument == nil {
                DashboardView(workspace: workspace)
                    .toolbar(removing: .sidebarToggle)
                    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                    .transition(.opacity)
            } else {
                NavigationSplitView(columnVisibility: columnVisibility) {
                    DocumentSidebarView(workspace: workspace)
                        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
                } detail: {
                    WorkspaceLayoutView(workspace: workspace)
                        .navigationTitle(workspace.windowTitle)
                        .toolbarTitleDisplayMode(.inline)
                        .toolbar(removing: .sidebarToggle)
                        .toolbar {
                            if !workspace.sidebarVisible {
                                ToolbarItem(placement: .navigation) {
                                    SidebarOptionsMenu(workspace: workspace)
                                }
                                .sharedBackgroundVisibility(.hidden)
                            }
                            GlassToolbarContent(workspace: workspace)
                        }
                        .mainToolbarChrome()
                }
                .navigationSplitViewStyle(.balanced)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: workspace.pdfDocument == nil)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.pathExtension.lowercased() == "pdf" else { return }
                Task { @MainActor in
                    workspace.openDocument(at: url)
                }
            }
            return true
        }
    }
}

#Preview {
    ContentView(workspace: WorkspaceViewModel())
}
