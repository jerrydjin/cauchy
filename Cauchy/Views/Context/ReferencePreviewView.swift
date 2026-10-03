import SwiftUI
import PDFKit

struct ReferencePreviewView: View {
    @Bindable var workspace: WorkspaceViewModel
    @State private var showsTranscription = false
    @State private var sourceImage: NSImage?
    @State private var sourceRegionImage: NSImage?
    @State private var isLoadingSource = false
    @State private var laterMentions: ReferenceMentionSearchResult?
    @State private var isSearchingLaterMentions = false
    @State private var laterMentionsError: String?
    @State private var showsLaterMentions = false

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
                } else if !workspace.referenceIndex.isEmpty {
                    referenceList
                } else {
                    ContentUnavailableView(
                        "Hover a Reference",
                        systemImage: "text.book.closed",
                        description: Text("Hover a theorem, equation, or figure citation.")
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

    private var referenceList: some View {
        List(workspace.referenceIndex.allBlocks, id: \.reference.key) { block in
            Button {
                workspace.contextEngine.showReferencePreview(block: block)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(block.title)
                    HStack(spacing: 5) {
                        Text("p. \(block.pageIndex + 1)")
                        if block.contentOrigin == .ocrCandidate {
                            Label("OCR candidate", systemImage: "viewfinder")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .overlay {
            if workspace.referenceIndex.allBlocks.isEmpty {
                ContentUnavailableView(
                    "No references found",
                    systemImage: "text.book.closed"
                )
            }
        }
        .accessibilityLabel("Indexed references")
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
                    Button("All references", systemImage: "chevron.left") {
                        workspace.contextEngine.passiveBlock = nil
                    }
                    .buttonStyle(.borderless)
                    .help("Return to the indexed reference list")

                    Text(block.title).font(.headline)
                    Spacer()
                    Button("Go to page \(block.pageIndex + 1)", systemImage: "arrow.up.forward") {
                        workspace.goToPage(block.pageIndex + 1)
                    }
                    .buttonStyle(.borderless)
                }
                evidenceStatus(for: block)
                if block.reference.kind == .figure {
                    Text("Caption label only · inspect the figure on the original page.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if block.contentOrigin != .ocrCandidate && block.reference.kind != .figure {
                    Picker("Reference view", selection: $showsTranscription) {
                        Text("Source evidence").tag(false)
                        Text(block.contentOrigin == .modelTranscription ? "AI formatted" : "Cleaned text").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                if showsTranscription, block.contentOrigin != .ocrCandidate,
                   block.reference.kind != .figure {
                    Text(block.contentOrigin == .modelTranscription
                        ? "Check symbols and meaning against the original page."
                        : "Lightly cleaned PDF text; check against the original page.")
                        .font(.caption).foregroundStyle(.secondary)
                    ReadingBlockCard(block: block, displayBody: block.formattedBody)
                } else {
                    if let evidence = block.evidence {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(evidence.effectiveSource == .visionOCR
                                ? "On-device OCR transcript (verify)"
                                : block.reference.kind == .figure
                                    ? "Printed caption heading"
                                    : "Verbatim PDF text")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(evidence.sourceExcerpt)
                                .font(.body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(14)
                        .background(ContentSurface.bubble, in: RoundedRectangle(cornerRadius: 12))
                    } else {
                        Text("This older index entry has no retained evidence. Re-index the document before relying on its transcription.")
                            .foregroundStyle(.secondary)
                    }

                    Divider().padding(.vertical, 2)
                    if let sourceRegionImage {
                        Text("Matched location on the page")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Image(nsImage: sourceRegionImage)
                            .resizable().scaledToFit()
                            .accessibilityLabel("Original PDF region showing \(block.title)")
                        Divider().padding(.vertical, 2)
                    }
                    laterMentionsView
                    Divider().padding(.vertical, 2)
                    Text("Original page")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if let sourceImage {
                        Image(nsImage: sourceImage)
                            .resizable().scaledToFit()
                            .accessibilityLabel("Original PDF page \(block.pageIndex + 1) for \(block.title)")
                    } else if isLoadingSource {
                        ProgressView("Loading original page…")
                    } else {
                        Text("Page preview unavailable. Open the source page to inspect this reference.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
        }
        .task(id: block) {
            showsLaterMentions = false
            sourceImage = nil
            sourceRegionImage = nil
            isLoadingSource = true
            defer { isLoadingSource = false }
            guard let page = workspace.pdfDocument?.page(at: block.pageIndex),
                  let data = page.dataRepresentation else { return }
            // A page reconstructed from dataRepresentation can extract different text
            // (and therefore have different character offsets). Resolve the match
            // against the original document before copying the page for rendering.
            let exact = block.evidence.flatMap {
                ReferenceEvidenceRegionResolver.exactRegion(for: $0, on: page)
            }
            let images = await Task.detached(priority: .userInitiated) { () -> (NSImage?, NSImage?) in
                guard let sourcePage = PDFDocument(data: data)?.page(at: 0) else { return (nil, nil) }
                let full = sourcePage.thumbnail(of: NSSize(width: 1200, height: 1600), for: .mediaBox)
                let region: NSImage?
                if let exact,
                   let rendered = PDFRegionRenderer.render(
                       page: sourcePage,
                       bounds: ReferenceEvidenceRegionResolver.contextRegion(for: exact),
                       highlight: exact.cgRect(in: sourcePage.bounds(for: .mediaBox))
                   ) {
                    region = NSImage(
                        cgImage: rendered,
                        size: NSSize(width: CGFloat(rendered.width) / 2, height: CGFloat(rendered.height) / 2)
                    )
                } else {
                    region = nil
                }
                return (full, region)
            }.value
            guard !Task.isCancelled else { return }
            sourceImage = images.0
            sourceRegionImage = images.1
        }
        .task(id: block) {
            laterMentions = nil
            laterMentionsError = nil
            isSearchingLaterMentions = true
            if let cached = workspace.referenceIndex.laterMentions(for: block.reference) {
                laterMentions = cached
                isSearchingLaterMentions = false
                return
            }
            guard let documentURL = workspace.pdfDocument?.documentURL else {
                isSearchingLaterMentions = false
                laterMentionsError = "The source PDF is unavailable for later-reference search."
                return
            }
            let reference = block.reference
            let pageIndex = block.pageIndex
            let definingEndOffset = block.evidence?.textLayerMatchEndOffset
            let search = Task.detached(priority: .utility) {
                try ReferenceMentionFinder.find(
                    documentURL: documentURL,
                    reference: reference,
                    after: pageIndex,
                    definingEndOffset: definingEndOffset
                )
            }
            do {
                let result = try await withTaskCancellationHandler {
                    try await search.value
                } onCancel: {
                    search.cancel()
                }
                guard !Task.isCancelled else { return }
                laterMentions = result
                isSearchingLaterMentions = false
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                laterMentionsError = error.localizedDescription
                isSearchingLaterMentions = false
            }
        }
    }

    @ViewBuilder
    private var laterMentionsView: some View {
        DisclosureGroup(isExpanded: $showsLaterMentions) {
            VStack(alignment: .leading, spacing: 8) {
                if isSearchingLaterMentions {
                    ProgressView("Checking later pages…")
                        .font(.caption)
                } else if let laterMentionsError {
                    Text(laterMentionsError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let laterMentions {
                    if laterMentions.mentions.isEmpty {
                        Text("No later mentions found in searchable PDF text.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(laterMentions.mentions) { mention in
                            Button {
                                workspace.goToReferenceMention(mention)
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Text("p. \(mention.pageIndex + 1)")
                                        .font(.caption.weight(.semibold))
                                        .fixedSize()
                                    Text(mention.context)
                                        .font(.caption)
                                        .lineLimit(3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "arrow.up.forward")
                                        .font(.caption)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Open the printed citation on page \(mention.pageIndex + 1)")
                        }
                    }
                    Text("Printed mentions only; no dependency claim.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if laterMentions.pagesWithoutText > 0 || laterMentions.unresolvedMatches > 0 || laterMentions.truncated {
                        Text("Search may be incomplete: \(laterMentions.pagesWithoutText) page(s) without searchable text, \(laterMentions.unresolvedMatches) unlocated match(es)\(laterMentions.truncated ? ", first 30 locations shown" : "").")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        } label: {
            Text("Later mentions\(laterMentions.map { " (\($0.mentions.count))" } ?? "")")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func evidenceStatus(for block: DocumentBlock) -> some View {
        if let evidence = block.evidence {
            if evidence.effectiveSource == .visionOCR {
                Label("OCR candidate · verify on page", systemImage: "viewfinder")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .help("Local OCR found this numbered heading and its page region. OCR can misread words, symbols, and digits; Cauchy does not use this transcript as answer evidence.")
            } else {
                let isSupported = evidence.status == .supported
                Label {
                    Text(block.reference.kind == .figure
                         ? (isSupported ? "Caption label located" : "Multiple caption labels")
                         : (isSupported ? "Reference label located" : "Multiple label matches"))
                } icon: {
                    Image(systemName: isSupported ? "checkmark.shield.fill" : "questionmark.diamond.fill")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(isSupported ? Color.green : Color.orange)
                .help(
                    block.reference.kind == .figure
                        ? "Cauchy located the printed caption label. The chart or image content has not been transcribed; inspect the original page."
                        : (isSupported
                            ? "Cauchy found one matching source occurrence in the PDF text."
                            : "Cauchy found \(evidence.occurrenceCount) matching occurrences. Inspect the page before relying on this transcription.")
                )
            }
        } else {
            Label("Evidence unavailable", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
        }
    }

    /// The index's own status line. A thin or wrong index is noticed here, on
    /// the entries themselves, so the re-index controls belong here and not
    /// only in the View menu.
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
        return provenance.summary
    }
}
