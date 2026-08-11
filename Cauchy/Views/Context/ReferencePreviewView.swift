import SwiftUI

struct ReferencePreviewView: View {
    @Bindable var workspace: WorkspaceViewModel

    var body: some View {
        VStack(spacing: 0) {
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

            if workspace.pdfDocument != nil {
                Divider()
                indexFooter
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

    /// The index's own status line. A thin or wrong index is noticed here, on
    /// the entries themselves, so the re-index controls belong here and not
    /// only in the View menu. Naming the builder matters: "on-device model" is
    /// the usual explanation for a weak index, and the fix is next to it.
    private var indexFooter: some View {
        HStack(spacing: 8) {
            Text(footerStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            Menu {
                Button("Rebuild Index") {
                    workspace.rebuildReferenceIndex()
                }

                Button("Re-index with Gemini") {
                    workspace.rebuildReferenceIndex(usingGemini: true)
                }
                .disabled(!workspace.canRebuildReferenceIndexWithGemini)
            } label: {
                Label("Re-index", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(workspace.isIndexingReferences)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .help(footerHelp)
    }

    private var footerStatus: String {
        if workspace.isIndexingReferences {
            return "Indexing… \(Int(workspace.referenceIndexProgress * 100))%"
        }
        if workspace.referenceIndexError != nil {
            return "Index unavailable"
        }
        guard let provenance = workspace.referenceIndexProvenance else {
            return "Not indexed yet"
        }
        return workspace.referenceIndexWarning == nil
            ? provenance.summary
            : "\(provenance.summary) · incomplete"
    }

    private var footerHelp: String {
        if let error = workspace.referenceIndexError { return error }
        if let warning = workspace.referenceIndexWarning { return warning }
        guard let provenance = workspace.referenceIndexProvenance else { return footerStatus }
        return provenance.isOnDevice && workspace.canRebuildReferenceIndexWithGemini
            ? "\(provenance.summary). Re-index with Gemini for a more accurate index."
            : provenance.summary
    }
}
