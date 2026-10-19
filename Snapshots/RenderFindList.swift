import AppKit
import Foundation
import SwiftUI

/// Renders Cmd-F for "Lemma 2" on arXiv:2610.04096. The four lemmas are the
/// printed statements on pages 3 and 4; DocumentFind builds the rows.
@main
enum RenderFindList {
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
        let fixture = root.appendingPathComponent("Snapshots/Fixtures/2610.04096-lemmas.json")
        let data = try Data(contentsOf: fixture)
        let lemmas = try JSONDecoder().decode([LemmaFixture].self, from: data)
        let entries = lemmas.map { lemma in
            DocumentFind.Entry(
                kind: .lemma,
                number: lemma.number,
                name: nil,
                body: lemma.body,
                pageIndex: lemma.pageIndex,
                anchor: "Lemma \(lemma.number)"
            )
        }
        let outcome = DocumentFind.search(query: "Lemma 2", entries: entries, sections: [])
        let labels = outcome.hits.map(\.label)
        guard labels == ["Lemma 2.1", "Lemma 2.2", "Lemma 2.3", "Lemma 2.4"] else {
            throw SnapshotError("unexpected rows: \(labels)")
        }
        guard !outcome.jumpsImmediately else {
            throw SnapshotError("several lemmas must stay listed")
        }

        let find = PDFFindModel()
        find.showSnapshotResults(query: "Lemma 2", hits: outcome.hits)

        NSApplication.shared.setActivationPolicy(.prohibited)
        let view = SnapshotChrome(
            caption: "arXiv:2610.04096  ·  Cmd-F “Lemma 2”",
            content: FindBarView(find: find)
        )
        try writePNG(view, to: output.appendingPathComponent("find-lemma-2.png"), minimumBytes: 3_000)
        for hit in outcome.hits {
            fputs("\(hit.label)  p.\(hit.pageIndex + 1)  \(hit.firstLine)\n", stdout)
        }
    }
}

private struct LemmaFixture: Decodable {
    var number: String
    var pageIndex: Int
    var body: String
}

private struct SnapshotChrome<Content: View>: View {
    var caption: String
    var content: Content

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            content
        }
        .padding(28)
        .frame(width: 460, alignment: .trailing)
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
