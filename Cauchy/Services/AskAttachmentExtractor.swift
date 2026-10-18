import AppKit
import Foundation
import PDFKit

/// Pulls the question text out of a problem sheet. PDFs use PDFKit's text
/// layer. Images and screenshots use the on-device Vision recognizer in
/// `OCRService`.
enum AskAttachmentExtractor {
    enum Failure: LocalizedError {
        case unsupportedType(String)
        case unreadable
        case noText

        var errorDescription: String? {
            switch self {
            case .unsupportedType(let ext):
                return "“.\(ext)” can’t be attached. Drop a PDF or an image of the question."
            case .unreadable:
                return "Couldn’t read that file."
            case .noText:
                return "No text could be read from that file."
            }
        }
    }

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "tif", "tiff", "heic", "webp", "bmp"
    ]

    static func extract(from url: URL) async throws -> AskProblemSheet {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent
        if ext == "pdf" {
            let text = try pdfText(at: url)
            return AskProblemSheet(fileName: name, extractedText: text)
        }
        if imageExtensions.contains(ext) {
            let text = try await imageText(at: url)
            return AskProblemSheet(fileName: name, extractedText: text)
        }
        throw Failure.unsupportedType(ext.isEmpty ? "file" : ext)
    }

    static func extractImage(_ image: CGImage, fileName: String) async throws -> AskProblemSheet {
        let result = try await OCRService.shared.recognizeText(in: image)
        let text = clipForStorage(result.rawText)
        guard !text.isEmpty else { throw Failure.noText }
        return AskProblemSheet(fileName: fileName, extractedText: text)
    }

    /// Joins PDF page strings in order and caps the stored sheet. Exposed so
    /// tests can cover clipping without a rendered page.
    static func combinePageTexts(_ pages: [String], characterLimit: Int = AskPromptBuilder.storedSheetCharacters) -> String {
        let joined = pages
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        return clipForStorage(joined, limit: characterLimit)
    }

    static func pdfText(at url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else { throw Failure.unreadable }
        var pages: [String] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            pages.append(page.string ?? "")
        }
        let text = combinePageTexts(pages)
        guard !text.isEmpty else { throw Failure.noText }
        return text
    }

    private static func imageText(at url: URL) async throws -> String {
        guard let image = NSImage(contentsOf: url), let cgImage = cgImage(from: image) else {
            throw Failure.unreadable
        }
        return try await extractImage(cgImage, fileName: url.lastPathComponent).extractedText
    }

    static func cgImage(from image: NSImage) -> CGImage? {
        var proposed = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
    }

    private static func clipForStorage(_ text: String, limit: Int = AskPromptBuilder.storedSheetCharacters) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit))
    }
}
