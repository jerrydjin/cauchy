import SwiftUI

struct GlassToolbarContent: ToolbarContent {
    @Bindable var workspace: WorkspaceViewModel
    @State private var pageFieldText = ""

    private var hasDocument: Bool {
        workspace.pdfDocument != nil
    }

    var body: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                workspace.closeDocument()
            } label: {
                Label("Home", systemImage: "house.fill")
            }
            .help("Return to Dashboard")
            
            Button {
                workspace.openDocument()
            } label: {
                Label("Open", systemImage: "doc")
            }

            if hasDocument {
                Button {
                    workspace.zoomOut()
                } label: {
                    Label("Zoom Out", systemImage: "minus.magnifyingglass")
                }

                Button {
                    workspace.zoomIn()
                } label: {
                    Label("Zoom In", systemImage: "plus.magnifyingglass")
                }

                Button {
                    workspace.zoomToFitWidth()
                } label: {
                    Label("Fit to Width", systemImage: "arrow.up.left.and.arrow.down.right")
                }

                Button {
                    workspace.goToPreviousPage()
                } label: {
                    Label("Previous Page", systemImage: "chevron.left")
                }
                .disabled(workspace.currentPage <= 1)

                TextField("", text: $pageFieldText)
                    .frame(width: 28)
                    .multilineTextAlignment(.center)
                    .font(.callout.monospacedDigit())
                    .onSubmit { commitPageField() }
                    .onChange(of: workspace.currentPage) { _, newValue in
                        pageFieldText = "\(newValue)"
                    }
                    .onAppear {
                        pageFieldText = "\(workspace.currentPage)"
                    }

                Button {
                    workspace.goToNextPage()
                } label: {
                    Label("Next Page", systemImage: "chevron.right")
                }
                .disabled(workspace.currentPage >= workspace.pageCount)

                // The 28pt slot is what keeps this off the glass capsule's
                // rounded end — a bare ring sits flush against it and gets
                // clipped, which is how the old circular ProgressView ended up
                // looking like a stray blue dot.
                if workspace.isIndexingReferences {
                    IndexProgressRing(progress: workspace.referenceIndexProgress)
                        .frame(width: 28, height: 28)
                        .help("Indexing document references for AI analysis (\(Int(workspace.referenceIndexProgress * 100))%)…")
                } else if let error = workspace.referenceIndexError {
                    // Without this the only sign of a failed index is the
                    // Reference tab, which the user may never open.
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .frame(width: 28, height: 28)
                        .help("Reference indexing failed — \(error)")
                        .accessibilityLabel("Reference indexing failed")
                } else if let warning = workspace.referenceIndexWarning {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .frame(width: 28, height: 28)
                        .help(warning)
                        .accessibilityLabel("Reference index incomplete")
                }
            }
        }
    }

    private func commitPageField() {
        guard let page = Int(pageFieldText.trimmingCharacters(in: .whitespaces)),
              page >= 1, page <= workspace.pageCount else {
            pageFieldText = "\(workspace.currentPage)"
            return
        }
        workspace.goToPage(page)
    }
}
