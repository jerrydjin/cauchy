import AppKit
import Foundation
import SwiftUI

/// Renders a citation hover from a synthetic bibliography. The cite is
/// "[QR23, Lemma 2.1]".
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
        let fixture = root.appendingPathComponent("Snapshots/Fixtures/synthetic-references.txt")
        let text = try String(contentsOf: fixture, encoding: .utf8)
        let entries = BibliographyIndex.entries(in: text)
        let citation = ExternalCitation(
            key: "QR23",
            author: nil,
            year: nil,
            qualifier: "Lemma 2.1",
            range: text.startIndex..<text.startIndex
        )
        guard let hover = BibliographyIndex.hoverText(for: citation, in: entries) else {
            throw SnapshotError("BibliographyIndex returned no hover for [QR23, Lemma 2.1]")
        }
        let lines = hover.components(separatedBy: "\n")
        guard lines == [
            "Synthetic tensor categories",
            "Q. Quinn, R. Rivera, and S. Santos, 2023",
            "Lemma 2.1 in the cited paper",
        ] else {
            throw SnapshotError("unexpected hover text: \(hover)")
        }

        NSApplication.shared.setActivationPolicy(.prohibited)
        let view = SnapshotChrome(
            caption: "Hover on [QR23, Lemma 2.1]",
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
