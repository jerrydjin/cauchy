import SwiftUI
import UniformTypeIdentifiers
import PDFKit

struct DashboardView: View {
    @Bindable var workspace: WorkspaceViewModel
    
    @State private var recentWorkspaces: [PersistedWorkspace] = []
    @State private var isHoveringDropZone = false
    
    let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 24)
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 48) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "book.pages")
                        .font(.system(size: 56, weight: .thin))
                        .foregroundStyle(.secondary)
                        .padding(.top, 80)
                    
                    Text("Cauchy")
                        .font(.system(size: 36, weight: .medium, design: .serif))
                    
                    Text("Mathematical PDF Workspace")
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
                
                // Recents Grid
                if !recentWorkspaces.isEmpty {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Recent")
                            .font(.title2.bold())
                            .padding(.leading, 4)
                        
                        LazyVGrid(columns: columns, spacing: 24) {
                            ForEach(recentWorkspaces, id: \.workspace.id) { persisted in
                                RecentDocumentCard(
                                    persisted: persisted,
                                    action: { open(persisted) }
                                )
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
        .onAppear(perform: loadWorkspaces)
        // Apply scroll edge effect so it feels deeply integrated with the macOS 27 window chrome
        .sidebarScrollEdgeEffect()
        .sidebarScrollContentInsets()
    }
    
    private func loadWorkspaces() {
        do {
            recentWorkspaces = try DocumentPersistenceService.shared.listAllWorkspaces()
        } catch {
            print("Failed to load recent workspaces: \(error)")
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url, url.pathExtension.lowercased() == "pdf" else { return }
            Task { @MainActor in
                workspace.openDocument(at: url)
            }
        }
        return true
    }
    
    private func open(_ persisted: PersistedWorkspace) {
        if let bookmark = persisted.bookmarkData,
           let url = try? DocumentPersistenceService.shared.resolveBookmark(bookmark) {
            workspace.openDocument(at: url)
        } else {
            workspace.openDocument(at: persisted.workspace.documentURL)
        }
    }
}

struct RecentDocumentCard: View {
    let persisted: PersistedWorkspace
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
                        Text(persisted.workspace.documentURL.deletingPathExtension().lastPathComponent)
                            .font(.headline)
                            .lineLimit(1)
                        
                        HStack {
                            Text("\(persisted.workspace.lastOpenedAt, style: .relative) ago")
                            Spacer()
                            if !persisted.workspace.highlights.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "pin.fill")
                                    Text("\(persisted.workspace.highlights.count)")
                                }
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    // Use vibrant text inside the card material
                    .vibrantContent()
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
        // Run in background to avoid hitching the UI
        let image = await Task.detached(priority: .background) { () -> NSImage? in
            var resolvedURL = persisted.workspace.documentURL
            if let bookmark = persisted.bookmarkData,
               let bookmarkURL = try? DocumentPersistenceService.shared.resolveBookmark(bookmark) {
                resolvedURL = bookmarkURL
            } else {
                _ = resolvedURL.startAccessingSecurityScopedResource()
            }
            
            defer { resolvedURL.stopAccessingSecurityScopedResource() }
            
            guard let document = PDFDocument(url: resolvedURL),
                  let page = document.page(at: 0) else {
                return nil
            }
            
            return PDFRegionRenderer.renderPageThumbnail(page: page, maxWidth: 300)
        }.value
        
        self.previewImage = image
    }
}

extension View {
    @ViewBuilder func vibrantContent() -> some View {
        if #available(macOS 14.0, *) {
            self.blendMode(.plusLighter) // A simple proxy for vibrant text within a material
        } else {
            self
        }
    }
}
