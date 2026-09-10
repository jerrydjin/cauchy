import SwiftUI
import PDFKit

struct ReferencePreviewView: View {
    @Bindable var workspace: WorkspaceViewModel
    @State private var showsTranscription = false
    @State private var sourceImage: NSImage?
    @State private var isLoadingSource = false

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
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(block.title).font(.headline)
                    Spacer()
                    Button("Go to page \(block.pageIndex + 1)", systemImage: "arrow.up.forward") {
                        workspace.goToPage(block.pageIndex + 1)
                    }
                    .buttonStyle(.borderless)
                }
                Picker("Reference view", selection: $showsTranscription) {
                    Text("Original page").tag(false)
                    Text("Index text").tag(true)
                }
                .pickerStyle(.segmented)
                if showsTranscription {
                    Text("AI transcription · compare with the original page for exact notation.")
                        .font(.caption).foregroundStyle(.secondary)
                    ReadingBlockCard(block: block, displayBody: block.formattedBody)
                } else if let sourceImage {
                    Image(nsImage: sourceImage)
                        .resizable().scaledToFit()
                        .accessibilityLabel("Original PDF page \(block.pageIndex + 1) for \(block.title)")
                } else if isLoadingSource {
                    ProgressView("Loading original page…")
                } else {
                    Text("Preview unavailable. Open the source page to read this reference.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .task(id: block.pageIndex) {
            sourceImage = nil
            isLoadingSource = true
            defer { isLoadingSource = false }
            guard let page = workspace.pdfDocument?.page(at: block.pageIndex),
                  let data = page.dataRepresentation else { return }
            let image = await Task.detached(priority: .userInitiated) {
                PDFDocument(data: data)?.page(at: 0)?.thumbnail(of: NSSize(width: 1200, height: 1600), for: .mediaBox)
            }.value
            guard !Task.isCancelled else { return }
            sourceImage = image
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
            // moment you most want to switch to the cloud, and rebuilding cancels
            // the in-flight task before starting.
            // Plain button style so nothing draws a rounded rect behind the
            // label's own surface. The chevron is drawn in the label rather
            // than left to `.menuIndicator`, which would sit outside it.
            Menu {
                ReferenceIndexMenuItems(workspace: workspace)
            } label: {
                // Same 32pt height and 14pt glyph as SidebarOptionsMenu and the
                // toolbar's status pill, so every control in the app reads at
                // one size. Only the width grows, for the chevron.
                HStack(spacing: 3) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 52, height: 32)
                // Same interactive glass as SidebarOptionsMenu — this is a
                // menu button and should feel like the app's other ones.
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
        return provenance.isOnDevice && workspace.canRebuildReferenceIndexWithCloud
            ? "\(provenance.summary). Re-index with \(workspace.cloudReindexVendor) for a more accurate index."
            : provenance.summary
    }
}
