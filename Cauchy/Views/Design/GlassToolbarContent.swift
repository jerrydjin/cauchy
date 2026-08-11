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

            }
        }

        // The index status rides in its own capsule rather than sharing the
        // navigation group's. It is a readout, not a control, and inside the
        // group it sat against the capsule's rounded end and got clipped.
        if hasDocument, hasIndexStatus {
            ToolbarSpacer(.fixed)

            ToolbarItem {
                indexStatusPill
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    private var hasIndexStatus: Bool {
        workspace.isIndexingReferences
            || workspace.referenceIndexError != nil
            || workspace.referenceIndexWarning != nil
    }

    /// A single circular glass pill. The toolbar gives every item its own
    /// rounded-rect glass background, which showed through behind the circle as
    /// a second, differently shaped layer; `.sharedBackgroundVisibility(.hidden)`
    /// turns that off so the only glass is the circle drawn here.
    ///
    /// Deliberately not a Button or Menu: `.buttonStyle(.plain)` also removes
    /// that background, but inside a ToolbarItem it stops the control from ever
    /// responding — a Menu never opens and a Button never fires. This is a
    /// readout, so a plain view is both honest and the one that renders right.
    private var indexStatusPill: some View {
        indexStatusSymbol
            .frame(width: 32, height: 32)
            .glassEffect(.regular, in: .circle)
            .help(indexStatusHelp)
    }

    @ViewBuilder
    private var indexStatusSymbol: some View {
        if workspace.isIndexingReferences {
            IndexProgressRing(progress: workspace.referenceIndexProgress)
        } else if workspace.referenceIndexError != nil {
            // Without this the only sign of a failed index is the Reference
            // tab, which the user may never open.
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.red)
        } else if workspace.referenceIndexWarning != nil {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.orange)
        }
    }

    private var indexStatusHelp: String {
        if workspace.isIndexingReferences {
            return "Indexing document references for AI analysis (\(Int(workspace.referenceIndexProgress * 100))%)…"
        }
        if let error = workspace.referenceIndexError {
            return "Reference indexing failed — \(error)"
        }
        return workspace.referenceIndexWarning ?? ""
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
