import AppKit
import Foundation
import SwiftUI

/// Renders the plain Cmd-F bar and the Cmd-K jump palette.
/// DocumentFind builds the rows; the palette is what a reader sees for "theorem".
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
        let fixture = root.appendingPathComponent("Snapshots/Fixtures/synthetic-lemmas.json")
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
        let previews = outcome.hits.map(\.firstLine)
        guard previews == [
            "A finite group of odd order is solvable.",
            "The product of two nilpotent ideals is nilpotent, and this…",
            "Every artinian module M∈ N has a finite composition series.",
            "The assignment f ↦ g gives a bijection of the sample set.",
        ] else {
            throw SnapshotError("unexpected previews: \(previews)")
        }
        guard previews.contains(where: { $0.hasSuffix("…") }) else {
            throw SnapshotError("a truncated preview must end with …")
        }
        guard !outcome.jumpsImmediately else {
            throw SnapshotError("several lemmas must stay listed")
        }

        let catalogue = jumpCatalogue()
        let jumpLabels = catalogue.map(\.label)
        guard jumpLabels == [
            "Theorem 1.3.3",
            "Theorem 2.3.1 (Cauchy or Cauchy-Goursat Theorem)",
            "Theorem 3.5.27 (Residue theorem)",
            "Theorem 9",
            "Lemma 2.4 (Zorn)",
            "Definition 3.2.1 (Homotopy Version of Cauchy's Theorem)",
        ] else {
            throw SnapshotError("unexpected jump rows: \(jumpLabels)")
        }
        let jumpPreviews = catalogue.map(\.firstLine)
        guard jumpPreviews == [
            "Let U ⊂ C be open, and suppose that f : U → C is holomorphic.",
            "Let U ⊂ C be a domain and γ be a closed curve.",
            "Suppose that U is an open set in C and γ is a closed curve.",
            "",
            "Every chain has an upper bound.",
            "Two cycles are homologous when their difference is a boundary.",
        ] else {
            throw SnapshotError("unexpected jump previews: \(jumpPreviews)")
        }
        for preview in jumpPreviews {
            if preview.contains("$") || preview.contains("{") || preview.contains("oldsymbol") || preview == "$$" {
                throw SnapshotError("preview still has markup: \(preview)")
            }
        }

        let find = PDFFindModel()
        find.showPlainSnapshot(query: "theorem", matchCount: 232)
        guard DocumentFind.textMatchLabel(count: find.matchCount, isSearching: find.isSearching) == "232 matches in the text" else {
            throw SnapshotError("find bar lost the match wording")
        }

        let palette = JumpPaletteModel()
        palette.showSnapshot(query: "", hits: catalogue)

        let findBar = SnapshotChrome(
            caption: "Cmd-F",
            content: FindBarView(find: find)
                .environment(\.rendersForSnapshot, true)
                .environment(\.colorScheme, .light)
        )
        let darkFindBar = SnapshotChrome(
            caption: "Cmd-F · dark",
            content: FindBarView(find: find)
                .environment(\.rendersForSnapshot, true)
                .environment(\.colorScheme, .dark)
                .padding(8)
                .background(Color.black)
        )
        let lightPalette = SnapshotChrome(
            caption: "Cmd-K Jump to",
            content: JumpPaletteView(palette: palette)
                .environment(\.rendersForSnapshot, true)
                .environment(\.colorScheme, .light)
        )
        let darkPalette = SnapshotChrome(
            caption: "Cmd-K Jump to · dark",
            content: JumpPaletteView(palette: palette)
                .environment(\.rendersForSnapshot, true)
                .environment(\.colorScheme, .dark)
                .padding(8)
                .background(Color.black)
        )
        // The list Cmd-F used to show, drawn from the same synthetic paper.
        let before = BeforeFindBar(query: "", hits: catalogue)
        let beforeLight = SnapshotChrome(
            caption: "Cmd-F before",
            content: before.environment(\.colorScheme, .light)
        )
        let beforeDark = SnapshotChrome(
            caption: "Cmd-F before · dark",
            content: before
                .environment(\.colorScheme, .dark)
                .padding(8)
                .background(Color.black)
        )

        try writePNG(findBar, to: output.appendingPathComponent("find-bar.png"), minimumBytes: 3_000)
        try writePNG(darkFindBar, to: output.appendingPathComponent("find-bar-dark.png"), minimumBytes: 3_000)
        try writePNG(lightPalette, to: output.appendingPathComponent("jump-palette.png"), minimumBytes: 8_000)
        try writePNG(darkPalette, to: output.appendingPathComponent("jump-palette-dark.png"), minimumBytes: 8_000)
        try writePNG(beforeLight, to: output.appendingPathComponent("find-before-light.png"), minimumBytes: 8_000)
        try writePNG(beforeDark, to: output.appendingPathComponent("find-before-dark.png"), minimumBytes: 8_000)
        let combined = HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 20) {
                findBar
                lightPalette
            }
            VStack(alignment: .leading, spacing: 20) {
                darkFindBar
                darkPalette
            }
        }
        .padding(8)
        .background(Color(white: 0.94))
        try writePNG(combined, to: output.appendingPathComponent("find-and-jump.png"), minimumBytes: 12_000)
        for hit in catalogue {
            fputs("\(hit.label)  p.\(hit.pageIndex + 1)  \(hit.firstLine)\n", stdout)
        }
    }

    private static func jumpCatalogue() -> [DocumentFind.Hit] {
        let entries = [
            DocumentFind.Entry(
                kind: .theorem,
                number: "1.3.3",
                name: "Theorem 1.3.3",
                body: "Let U $\\subset C$ be open, and suppose that f : U \\to C is holomorphic.",
                pageIndex: 17,
                anchor: "Theorem 1.3.3"
            ),
            DocumentFind.Entry(
                kind: .theorem,
                number: "2.3.1",
                name: "Cauchy or Cauchy-Goursat Theorem",
                body: "Let U $\\subset C$ be a domain and $\\gamma$ be a closed curve.",
                pageIndex: 47,
                anchor: "Theorem 2.3.1"
            ),
            DocumentFind.Entry(
                kind: .theorem,
                number: "3.5.27",
                name: "Residue theorem",
                body: "Suppose that U is an open set in C and \\gamma is a closed curve.",
                pageIndex: 83,
                anchor: "Theorem 3.5.27"
            ),
            DocumentFind.Entry(
                kind: .theorem,
                number: "9",
                name: "Theorem 9",
                body: "$$",
                pageIndex: 107,
                anchor: "Theorem 9",
                sourceExcerpt: "$oldsymbol{"
            ),
            DocumentFind.Entry(
                kind: .lemma,
                number: "2.4",
                name: "Zorn",
                body: "Every chain has an upper bound.",
                pageIndex: 11,
                anchor: "Lemma 2.4"
            ),
            DocumentFind.Entry(
                kind: .definition,
                number: "3.2.1",
                name: "Homotopy Version of Cauchy's Theorem",
                body: "$$",
                pageIndex: 66,
                anchor: "Definition 3.2.1",
                sourceExcerpt: "Two cycles are homologous when their difference is a boundary."
            ),
        ]
        return DocumentFind.jumpHits(query: "", entries: entries, sections: [])
    }
}

private struct LemmaFixture: Decodable {
    var number: String
    var pageIndex: Int
    var body: String
}

/// Cmd-F as it was on main: the text field and the indexed list in one bar.
/// The snapshot draws it from the same synthetic paper as the palette.
private struct BeforeFindBar: View {
    var query: String
    var hits: [DocumentFind.Hit]
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            capsule
            if !hits.isEmpty {
                namedList
            }
        }
        .onAppear { isFieldFocused = true }
    }

    private var capsule: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            Text(query.isEmpty ? "Find in document" : query)
                .font(.body)
                .foregroundStyle(query.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .frame(width: 200, alignment: .leading)

            if !query.isEmpty {
                Text(matchLabel)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }

            Divider()
                .frame(height: 16)

            GlassIconButton(systemName: "chevron.up", accessibilityLabel: "Previous Match") {}
                .disabled(true)
            GlassIconButton(systemName: "chevron.down", accessibilityLabel: "Next Match") {}
                .disabled(true)
            GlassIconButton(systemName: "xmark", accessibilityLabel: "Close Find Bar") {}
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(in: .capsule)
    }

    private var namedList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(groupedHits, id: \.title) { group in
                Text(group.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(group.hits) { hit in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(hit.label)
                                .font(.callout.weight(.medium))
                            Spacer(minLength: 8)
                            Text("p. \(hit.pageIndex + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if !hit.firstLine.isEmpty {
                            Text(hit.firstLine)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .frame(width: 360, alignment: .leading)
        .glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var groupedHits: [(title: String, hits: [DocumentFind.Hit])] {
        var titles: [String] = []
        var grouped: [String: [DocumentFind.Hit]] = [:]
        for hit in hits {
            if grouped[hit.group] == nil { titles.append(hit.group) }
            grouped[hit.group, default: []].append(hit)
        }
        return titles.map { ($0, grouped[$0] ?? []) }
    }

    private var matchLabel: String {
        if hits.isEmpty { return "Not found" }
        return "\(hits.count) named"
    }
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
        .frame(width: 640, alignment: .trailing)
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
