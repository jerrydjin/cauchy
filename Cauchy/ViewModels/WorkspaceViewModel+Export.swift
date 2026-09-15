import AppKit
import Foundation
import UniformTypeIdentifiers

private let reopenLastDocumentKey = "reading.reopenLastDocument"

extension UTType {
    static let cauchyReadingSession = UTType(
        exportedAs: "com.cauchy.reading-session",
        conformingTo: .package
    )
}

@MainActor
extension WorkspaceViewModel {
    var canExportHighlights: Bool {
        pdfDocument != nil && !highlightStore.highlights.isEmpty
    }

    var canExportReadingSession: Bool {
        pdfDocument != nil && workspace?.documentURL != nil
    }

    // MARK: - Reading session handoff

    func exportReadingSession() {
        guard canExportReadingSession else { return }
        // Capture the live viewport and highlight store before taking the
        // snapshot; the normal persistence debounce may not have fired yet.
        persistWorkspace()
        guard let snapshot = workspace else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.cauchyReadingSession]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "\(documentTitle).\(ReadingSessionPackageService.filenameExtension)"
        panel.message = "Save the PDF and your reading progress for another Mac"
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        let sourcePDF = snapshot.documentURL
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try ReadingSessionPackageService.write(
                        sourcePDF: sourcePDF,
                        destination: destination,
                        workspace: snapshot
                    )
                }.value
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func openReadingSession() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.cauchyReadingSession]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Open a Cauchy reading session"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await openReadingSession(at: url) }
    }

    func openReadingSession(at url: URL) async {
        do {
            let imported = try await persistence.importReadingSession(from: url)
            await openDocument(
                at: imported.workspace.documentURL,
                selecting: nil,
                adopting: imported
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Markdown

    func exportHighlightsAsMarkdown() {
        guard canExportHighlights else { return }
        let text = HighlightExportService.markdown(
            documentTitle: documentTitle,
            highlights: highlightStore.highlights
        )

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "\(documentTitle) — Highlights.md"
        panel.message = "Export highlights and conversations as Markdown"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = "Could not write the Markdown file: \(error.localizedDescription)"
        }
    }

    func copyHighlightsAsMarkdown() {
        guard canExportHighlights else { return }
        writeToPasteboard(
            HighlightExportService.markdown(
                documentTitle: documentTitle,
                highlights: highlightStore.highlights
            )
        )
    }

    func copyThreadAsMarkdown(_ highlight: Highlight) {
        writeToPasteboard(
            HighlightExportService.markdown(for: highlight, documentTitle: documentTitle)
        )
    }

    private func writeToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Annotated PDF

    /// Writes a copy of the PDF with the highlights baked in as real PDF
    /// annotations. The app's own highlights live only in its workspace file,
    /// so without this a marked-up document opens clean everywhere else.
    func exportAnnotatedPDFCopy() {
        guard canExportHighlights, let sourceURL = workspace?.documentURL else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(documentTitle) — Highlighted.pdf"
        panel.message = "Save a copy of the PDF with your highlights in it"
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        let highlights = highlightStore.highlights
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try HighlightExportService.writeAnnotatedPDF(
                        source: sourceURL,
                        destination: destination,
                        highlights: highlights
                    )
                }.value
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Session restore

    /// Default on: a reader who was half way through a paper yesterday means to
    /// carry on with it, not to be shown a grid of covers.
    static var reopensLastDocumentAtLaunch: Bool {
        get {
            UserDefaults.standard.object(forKey: reopenLastDocumentKey) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: reopenLastDocumentKey)
        }
    }

    /// Reopens whatever was last being read. Silent about every failure: if the
    /// file is gone or unreadable the dashboard is the right thing to show, and
    /// an alert on launch about a document nobody asked for is not.
    func restoreLastSession() async {
        guard !CauchyApp.isHostingTests else { return }
        guard Self.reopensLastDocumentAtLaunch, pdfDocument == nil else { return }
        guard let summary = await DocumentPersistenceService.shared.listWorkspaceSummaries().first else { return }

        var url = summary.documentURL
        if let bookmark = summary.bookmarkData,
           let resolved = try? DocumentPersistenceService.shared.resolveBookmark(bookmark) {
            url = resolved
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        await openDocument(at: url, selecting: nil)
    }
}
