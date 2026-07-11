import PDFKit
import SwiftUI

struct DocumentSidebarView: View {
    @Bindable var workspace: WorkspaceViewModel

    var body: some View {
        Group {
            if let document = workspace.pdfDocument {
                switch effectiveSidebarMode {
                case .thumbnails:
                    PDFThumbnailsSidebarView(
                        document: document,
                        currentPageIndex: workspace.viewportCoordinator.viewport.pageIndex,
                        thumbnailCache: workspace.pageThumbnailCache,
                        onSelectPage: { workspace.goToPage($0 + 1) }
                    )
                case .tableOfContents:
                    PDFTableOfContentsSidebarView(
                        document: document,
                        onSelectDestination: { workspace.navigateToDestination($0) }
                    )
                case .highlightsAndNotes:
                    PDFThumbnailsSidebarView(
                        document: document,
                        currentPageIndex: workspace.viewportCoordinator.viewport.pageIndex,
                        thumbnailCache: workspace.pageThumbnailCache,
                        onSelectPage: { workspace.goToPage($0 + 1) }
                    )
                case .contactSheet:
                    PDFContactSheetSidebarView(
                        document: document,
                        currentPageIndex: workspace.viewportCoordinator.viewport.pageIndex,
                        thumbnailCache: workspace.pageThumbnailCache,
                        onSelectPage: { workspace.goToPage($0 + 1) }
                    )
                }
            } else {
                ContentUnavailableView(
                    "No Document",
                    systemImage: "sidebar.left",
                    description: Text("Open a PDF to browse pages and highlights.")
                )
            }
        }
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            if workspace.sidebarVisible {
                ToolbarSpacer(.flexible, placement: .primaryAction)
                ToolbarItem(placement: .primaryAction) {
                    SidebarOptionsMenu(workspace: workspace)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .sidebarToolbarChrome()
    }

    private var effectiveSidebarMode: SidebarContentMode {
        workspace.sidebarContentMode == .highlightsAndNotes ? .thumbnails : workspace.sidebarContentMode
    }
}
