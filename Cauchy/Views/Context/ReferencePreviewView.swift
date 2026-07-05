import SwiftUI

struct ReferencePreviewView: View {
    @Bindable var workspace: WorkspaceViewModel

    var body: some View {
        Group {
            if let block = workspace.contextEngine.passiveBlock {
                formattedView(block: block)
            } else if let error = workspace.referenceIndexError {
                ContentUnavailableView {
                    Label("Reference Index Failed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                }
            } else if workspace.isIndexingReferences {
                ContentUnavailableView {
                    ProgressView()
                } description: {
                    Text("Indexing references…")
                }
            } else {
                ContentUnavailableView(
                    "Hover a Reference",
                    systemImage: "text.book.closed",
                    description: Text("Hover a theorem, lemma, or equation cite like (1.4).")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func formattedView(block: DocumentBlock) -> some View {
        ScrollView {
            ReadingBlockCard(block: block, displayBody: block.formattedBody)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
    }
}
