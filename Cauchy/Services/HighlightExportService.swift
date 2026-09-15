import Foundation
import PDFKit

enum HighlightExportError: LocalizedError {
    case cannotOpenSource
    case cannotWriteCopy

    var errorDescription: String? {
        switch self {
        case .cannotOpenSource:
            "The PDF could not be reopened to write the copy."
        case .cannotWriteCopy:
            "The annotated copy could not be written."
        }
    }
}

/// Gets a reading session out of the app: highlights and their conversations as
/// Markdown, or the PDF itself with the highlights painted in so they survive
/// in Preview and for whoever the file is sent to.
enum HighlightExportService {
    // MARK: - Markdown

    /// Highlights in reading order — page order, then when they were made —
    /// rather than the panel's most-recently-touched order, because a document
    /// read start to finish is what the export is a record of.
    nonisolated static func readingOrder(_ highlights: [Highlight]) -> [Highlight] {
        highlights.sorted {
            $0.pageIndex == $1.pageIndex
                ? $0.createdAt < $1.createdAt
                : $0.pageIndex < $1.pageIndex
        }
    }

    nonisolated static func markdown(
        documentTitle: String,
        highlights: [Highlight],
        exportedAt: Date = Date()
    ) -> String {
        let ordered = readingOrder(highlights)
        var out = "# \(documentTitle)\n\n"

        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        let count = ordered.count == 1 ? "1 highlight" : "\(ordered.count) highlights"
        out += "*\(count) · exported from Cauchy on \(formatter.string(from: exportedAt))*\n"

        for highlight in ordered {
            out += "\n---\n\n"
            out += body(of: highlight, headingLevel: 2)
        }
        return out
    }

    /// One thread on its own, for "Copy as Markdown" on a single row.
    nonisolated static func markdown(for highlight: Highlight, documentTitle: String) -> String {
        "# \(documentTitle)\n\n" + body(of: highlight, headingLevel: 2)
    }

    nonisolated private static func body(of highlight: Highlight, headingLevel: Int) -> String {
        let hashes = String(repeating: "#", count: headingLevel)
        var out = "\(hashes) \(highlight.displayName)\n\n"
        out += "**Page \(highlight.pageIndex + 1)**"
        if highlight.color != .default {
            out += " · \(highlight.color.displayName)"
        }
        out += "\n\n"

        let passage = highlight.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !passage.isEmpty {
            out += blockQuote(passage) + "\n\n"
        }

        if let note = highlight.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            out += "**Note:** \(note)\n\n"
        }

        for message in highlight.messages {
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            switch message.role {
            case .user:
                out += "**Q:** \(content)\n\n"
            case .assistant:
                out += "\(content)\n\n"
            }
        }
        return out
    }

    /// Every line prefixed, so a passage that wrapped across several lines in
    /// the PDF stays one quote instead of breaking out of it half way down.
    nonisolated private static func blockQuote(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { $0.isEmpty ? ">" : "> \($0)" }
            .joined(separator: "\n")
    }

    // MARK: - Annotated PDF

    /// Writes a copy of the PDF with the highlights painted into it. Reopens
    /// the file rather than reusing the live `PDFDocument`, so the copy carries
    /// no selection state and the reader's own document is never touched.
    nonisolated static func writeAnnotatedPDF(
        source: URL,
        destination: URL,
        highlights: [Highlight]
    ) throws {
        guard let document = PDFDocument(url: source) else {
            throw HighlightExportError.cannotOpenSource
        }
        // No active highlight: in an exported copy every highlight is equal,
        // and the stronger active tint would read as a mistake.
        HighlightAnnotationService.sync(document: document, highlights: highlights, activeID: nil)
        guard document.write(to: destination) else {
            throw HighlightExportError.cannotWriteCopy
        }
    }
}

// MARK: - Portable reading session

enum ReadingSessionPackageError: LocalizedError {
    case invalidPackage
    case unsupportedVersion
    case cannotWritePackage

    var errorDescription: String? {
        switch self {
        case .invalidPackage:
            "This Cauchy reading session is incomplete or damaged."
        case .unsupportedVersion:
            "This reading session was created by a newer version of Cauchy."
        case .cannotWritePackage:
            "The reading session could not be written."
        }
    }
}

struct ReadingSessionPackage: Codable, Sendable {
    var formatVersion: Int
    var documentFilename: String
    var workspace: DocumentWorkspace
}

/// A `.cauchyreading` package is deliberately ordinary files in a directory:
/// the original PDF plus a JSON snapshot of the page, zoom, highlights, and
/// conversations. It can travel through AirDrop or iCloud Drive without an
/// account or a Cauchy server, and a damaged manifest never touches the PDF.
enum ReadingSessionPackageService {
    static let filenameExtension = "cauchyreading"
    static let manifestFilename = "session.json"
    static let currentFormatVersion = 1

    nonisolated static func write(
        sourcePDF: URL,
        destination: URL,
        workspace: DocumentWorkspace
    ) throws {
        let manager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        let temporary = parent.appendingPathComponent(
            ".cauchy-reading-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? manager.removeItem(at: temporary) }

        do {
            try manager.createDirectory(at: temporary, withIntermediateDirectories: false)

            let documentFilename = sourcePDF.lastPathComponent
            guard !documentFilename.isEmpty,
                  documentFilename.lowercased().hasSuffix(".pdf")
            else { throw ReadingSessionPackageError.invalidPackage }

            try manager.copyItem(
                at: sourcePDF,
                to: temporary.appendingPathComponent(documentFilename)
            )

            // The source machine's absolute path and bookmark are neither
            // useful nor desirable in a portable file. Import always points
            // the snapshot at its own managed PDF copy.
            var portableWorkspace = workspace
            portableWorkspace.documentURL = URL(fileURLWithPath: documentFilename)
            let package = ReadingSessionPackage(
                formatVersion: currentFormatVersion,
                documentFilename: documentFilename,
                workspace: portableWorkspace
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(package).write(
                to: temporary.appendingPathComponent(manifestFilename),
                options: .atomic
            )

            if manager.fileExists(atPath: destination.path) {
                _ = try manager.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try manager.moveItem(at: temporary, to: destination)
            }
        } catch let error as ReadingSessionPackageError {
            throw error
        } catch {
            throw ReadingSessionPackageError.cannotWritePackage
        }
    }

    nonisolated static func read(from packageURL: URL) throws -> (ReadingSessionPackage, URL) {
        let manifestURL = packageURL.appendingPathComponent(manifestFilename)
        var packageIsDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: packageURL.path,
            isDirectory: &packageIsDirectory
        ), packageIsDirectory.boolValue,
              let data = try? Data(contentsOf: manifestURL)
        else { throw ReadingSessionPackageError.invalidPackage }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let package = try? decoder.decode(ReadingSessionPackage.self, from: data)
        else { throw ReadingSessionPackageError.invalidPackage }
        guard package.formatVersion <= currentFormatVersion else {
            throw ReadingSessionPackageError.unsupportedVersion
        }

        let filename = package.documentFilename
        guard filename == URL(fileURLWithPath: filename).lastPathComponent,
              filename.lowercased().hasSuffix(".pdf")
        else { throw ReadingSessionPackageError.invalidPackage }

        let documentURL = packageURL.appendingPathComponent(filename)
        let values = try? documentURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values?.isRegularFile == true,
              values?.isSymbolicLink != true
        else { throw ReadingSessionPackageError.invalidPackage }
        return (package, documentURL)
    }
}
