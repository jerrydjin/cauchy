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
                    indexingState
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

    /// Indexing owns the empty state rather than the footer: a long build is
    /// the whole story of this panel while it runs, and a bar carries "how far
    /// along" far better than a percentage tucked into a status line.
    private var indexingState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.book.closed")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("Indexing references")
                .font(.headline)

            ProgressView(value: workspace.referenceIndexProgress)
                .progressViewStyle(.linear)
                .frame(maxWidth: 200)
                .animation(.easeOut(duration: 0.3), value: workspace.referenceIndexProgress)

            Text("\(Int(workspace.referenceIndexProgress * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
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
            // Silent while a build runs — the empty state above is already
            // showing the bar, and saying it twice just crowds the panel.
            Text(footerStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            // Deliberately live during a build: a slow on-device index is the
            // moment you most want to switch to Gemini, and rebuilding cancels
            // the in-flight task before starting.
            // Same recipe as SidebarOptionsMenu — glass on the label, plain
            // button style so nothing draws a rounded rect behind it. The
            // chevron is drawn in the label rather than left to
            // `.menuIndicator`, which sits outside the glass.
            Menu {
                ReferenceIndexMenuItems(workspace: workspace)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 46, height: 28)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Re-index document")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .help(footerHelp)
    }

    private var footerStatus: String {
        if workspace.isIndexingReferences {
            return ""
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
