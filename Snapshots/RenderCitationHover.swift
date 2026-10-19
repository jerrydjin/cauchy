import AppKit
import Foundation
import SwiftUI

/// Renders the citation hover for arXiv:2610.04096, using the PDF text layer
/// and BibliographyIndex. The cite is the printed "[BEO23, Conjecture 1.4]".
@main
enum RenderCitationHover {
    @MainActor
    static func main() {
        do {
            try render()
        } catch {
            fputs("snapshot failed: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    @MainActor
    private static func render() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
        let output = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "Snapshots/out")
        let fixture = root.appendingPathComponent("Snapshots/Fixtures/2610.04096-references.txt")
        let text = try String(contentsOf: fixture, encoding: .utf8)
        let entries = BibliographyIndex.entries(in: text)
        let citation = ExternalCitation(
            key: "BEO23",
            author: nil,
            year: nil,
            qualifier: "Conjecture 1.4",
            range: text.startIndex..<text.startIndex
        )
        guard let hover = BibliographyIndex.hoverText(for: citation, in: entries) else {
            throw SnapshotError("BibliographyIndex returned no hover for [BEO23, Conjecture 1.4]")
        }
        guard hover.contains("Benson"), hover.contains("2023"), hover.contains("Conjecture 1.4 in the cited paper") else {
            throw SnapshotError("unexpected hover text: \(hover)")
        }

        NSApplication.shared.setActivationPolicy(.prohibited)
        let view = SnapshotChrome(
            caption: "arXiv:2610.04096  ·  hover on [BEO23, Conjecture 1.4]",
            content: CitationHoverPopover(text: hover)
        )
        try writePNG(view, to: output.appendingPathComponent("citation-hover.png"), minimumBytes: 2_000)
        fputs("hover text:\n\(hover)\n", stdout)
    }
}

private struct SnapshotChrome<Content: View>: View {
    var caption: String
    var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
        }
        .padding(28)
        .background(Color(white: 0.94))
    }
}

private struct SnapshotError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

@MainActor
private func writePNG<V: View>(_ view: V, to url: URL, minimumBytes: Int) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    renderer.isOpaque = true
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        throw SnapshotError("ImageRenderer produced no PNG")
    }
    guard png.count >= minimumBytes, rep.pixelsWide > 40, rep.pixelsHigh > 40 else {
        throw SnapshotError("PNG is \(png.count) bytes, \(rep.pixelsWide)x\(rep.pixelsHigh)")
    }
    try png.write(to: url)
    fputs("wrote \(url.path) (\(png.count) bytes, \(rep.pixelsWide)x\(rep.pixelsHigh))\n", stdout)
}
