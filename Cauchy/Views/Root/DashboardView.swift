import SwiftUI
import UniformTypeIdentifiers
import PDFKit

struct DashboardView: View {
    @Bindable var workspace: WorkspaceViewModel
    
    @State private var recentWorkspaces: [WorkspaceSummary] = []
    @State private var isHoveringDropZone = false
    @AppStorage("library.hiddenRecents") private var hiddenRecents = ""
    @State private var showHiddenRecents = false

    private var visibleRecents: [WorkspaceSummary] {
        recentWorkspaces.filter { showHiddenRecents || !hiddenRecents.split(separator: ",").contains(Substring($0.workspaceID.uuidString)) }
    }

    @State private var searchText = ""
    @State private var searchResults: [LibrarySearchResult] = []
    @State private var isSearching = false
    
    let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 24)
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if recentWorkspaces.isEmpty {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "book.pages")
                            .font(.system(size: 56, weight: .thin))
                            .foregroundStyle(.secondary)
                            .padding(.top, 80)
                    
                        Text("Cauchy")
                            .font(.system(size: 36, weight: .medium, design: .serif))
                    
                        Text("A workspace for papers and textbooks")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                
                    // Primary action (Drop zone & Open button)
                    GlassEffectContainer {
                        VStack(spacing: 16) {
                            Image(systemName: "arrow.down.doc.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(isHoveringDropZone ? Color.accentColor : Color.secondary)
                        
                            Text("Drop a PDF here")
                                .font(.headline)
                        
                            Text("or")
                                .foregroundStyle(.tertiary)
                        
                            Button {
                                workspace.openDocument()
                            } label: {
                                Text("Open PDF…")
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.glassProminent)
                            .keyboardShortcut("o", modifiers: .command)
                        }
                        .padding(48)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .glassEffect(in: .rect(cornerRadius: 24))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(
                                isHoveringDropZone ? Color.accentColor : Color.clear,
                                lineWidth: 2
                            )
                    }
                    .onDrop(of: [.fileURL], isTargeted: $isHoveringDropZone) { providers in
                        return handleDrop(providers: providers)
                    }
                
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Library").font(.largeTitle.weight(.semibold))
                            Text("Continue reading, or find a passage in your notes.")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open PDF…") { workspace.openDocument() }
                            .buttonStyle(.glassProminent)
                    }
                    .padding(.top, 32)
                }

                LibrarySearchField(text: $searchText)

                if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    searchResultsSection
                } else if !recentWorkspaces.isEmpty {
                    // Recents grid
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Text("Recent").font(.title2.bold())
                            Spacer()
                            if !hiddenRecents.isEmpty {
                                Toggle("Show hidden", isOn: $showHiddenRecents).toggleStyle(.checkbox)
                            }
                        }
                        
                        LazyVGrid(columns: columns, spacing: 24) {
                            ForEach(visibleRecents, id: \.workspaceID) { summary in
                                RecentDocumentCard(
                                    summary: summary,
                                    action: { open(summary) }
                                )
                                .contextMenu {
                                    Button(isHidden(summary) ? "Show in Recents" : "Hide from Recents") {
                                        var ids = Set(hiddenRecents.split(separator: ",").map(String.init))
                                        if isHidden(summary) { ids.remove(summary.workspaceID.uuidString) }
                                        else { ids.insert(summary.workspaceID.uuidString) }
                                        hiddenRecents = ids.sorted().joined(separator: ",")
                                    }
                                }
                            }
                        }
                    }
                }
                
                Spacer(minLength: 80)
            }
            .padding(.horizontal, 64)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await loadWorkspaces() }
        .task(id: searchText) { await runSearch() }
        // Apply scroll edge effect so it feels deeply integrated with the macOS 27 window chrome
        .sidebarScrollEdgeEffect()
        .sidebarScrollContentInsets()
    }

    /// Highlights and conversations from every document in the library, so a
    /// half-remembered passage is findable without first remembering which
    /// paper it was in.
    @ViewBuilder
    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                Text("Across All Documents")
                    .font(.title2.bold())
                if isSearching {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.leading, 4)

            if searchResults.isEmpty {
                if !isSearching {
                    ContentUnavailableView.search(text: searchText)
                        .frame(height: 220)
                }
            } else {
                VStack(spacing: 1) {
                    ForEach(searchResults) { result in
                        LibrarySearchResultRow(result: result) { open(result) }
                    }
                }
            }
        }
    }

    private func runSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }
        // Every keystroke reruns this task; the pause keeps a library of
        // hundreds of documents from being decoded once per letter typed.
        try? await Task.sleep(for: .milliseconds(220))
        guard !Task.isCancelled else { return }

        isSearching = true
        let results = await LibrarySearchService.search(query: query)
        guard !Task.isCancelled else { return }
        searchResults = results
        isSearching = false
    }

    private func open(_ result: LibrarySearchResult) {
        Task {
            var url = result.documentURL
            if let bookmark = result.bookmarkData,
               let resolved = try? DocumentPersistenceService.shared.resolveBookmark(bookmark) {
                url = resolved
            }
            await workspace.openDocument(at: url, selecting: result.highlight.id)
        }
    }

    private func isHidden(_ summary: WorkspaceSummary) -> Bool {
        hiddenRecents.split(separator: ",").contains(Substring(summary.workspaceID.uuidString))
    }

    private func loadWorkspaces() async {
        recentWorkspaces = await DocumentPersistenceService.shared.listWorkspaceSummaries()
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url, url.pathExtension.lowercased() == "pdf" else { return }
            Task { @MainActor in
                await workspace.openDocument(at: url)
            }
        }
        return true
    }

    private func open(_ summary: WorkspaceSummary) {
        Task {
            if let bookmark = summary.bookmarkData,
               let url = try? DocumentPersistenceService.shared.resolveBookmark(bookmark) {
                await workspace.openDocument(at: url)
            } else {
                await workspace.openDocument(at: summary.documentURL)
            }
        }
    }
}

struct RecentDocumentCard: View {
    let summary: WorkspaceSummary
    let action: () -> Void
    
    @State private var isHovering = false
    @State private var previewImage: NSImage?
    
    var body: some View {
        Button(action: action) {
            GlassEffectContainer {
                VStack(alignment: .leading, spacing: 0) {
                    // Preview Area
                    ZStack {
                        Color(nsColor: .underPageBackgroundColor).opacity(0.5)
                        
                        if let previewImage = previewImage {
                            Image(nsImage: previewImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .shadow(radius: 4, y: 2)
                                .padding(16)
                        } else {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                    
                    Divider()
                    
                    // Metadata Area
                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.documentURL.deletingPathExtension().lastPathComponent)
                            .font(.headline)
                            .lineLimit(2, reservesSpace: true)
                            .help(summary.documentURL.deletingPathExtension().lastPathComponent)

                        HStack {
                            Text("\(summary.lastOpenedAt, style: .relative) ago")
                            Spacer()
                            if summary.highlightCount > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "pin.fill")
                                    Text("\(summary.highlightCount)")
                                }
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(16)
                }
            }
            .glassEffect(in: .rect(cornerRadius: 16))
            .shadow(radius: isHovering ? 12 : 4, y: isHovering ? 6 : 2)
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .task { await generatePreview() }
    }
    
    @MainActor
    private func generatePreview() async {
        let summary = summary
        let previewURL = DocumentPersistenceService.shared.thumbnailURL(
            workspaceID: summary.workspaceID,
            filename: "preview.png"
        )

        // Run in background to avoid hitching the UI
        let image = await Task.detached(priority: .background) { () -> NSImage? in
            // Fast path: opening the document writes this once (see
            // WorkspaceViewModel.generateDashboardPreviewIfNeeded).
            if let cached = NSImage(contentsOf: previewURL) {
                return cached
            }

            // Fallback for workspaces saved before previews existed: render
            // once from the PDF and persist it so this never runs again.
            var resolvedURL = summary.documentURL
            var didStartAccess = false
            if let bookmark = summary.bookmarkData,
               let bookmarkURL = try? DocumentPersistenceService.shared.resolveBookmark(bookmark) {
                resolvedURL = bookmarkURL
            } else {
                didStartAccess = resolvedURL.startAccessingSecurityScopedResource()
            }

            // Only balance a start that actually happened — these calls are
            // reference-counted, so an extra stop can revoke access held elsewhere.
            defer {
                if didStartAccess {
                    resolvedURL.stopAccessingSecurityScopedResource()
                }
            }

            guard let document = PDFDocument(url: resolvedURL),
                  let page = document.page(at: 0),
                  let rendered = PDFRegionRenderer.renderFullPage(page, maxDimension: 600) else {
                return nil
            }

            try? FileManager.default.createDirectory(
                at: previewURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? PDFRegionRenderer.saveThumbnail(rendered, to: previewURL)

            let pageBounds = page.bounds(for: .mediaBox)
            return NSImage(cgImage: rendered, size: pageBounds.size)
        }.value

        self.previewImage = image
    }
}
