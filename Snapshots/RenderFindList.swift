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
        let rouche = DocumentFind.namesForDisplay(
            DocumentFind.displayNames(kind: .theorem, number: "3.6.3", name: "Rouch\u{00B4}e")
        ).names
        guard rouche == ["Rouché"] else {
            throw SnapshotError("Rouché accent still broken: \(rouche)")
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
                .environment(\.snapshotReservesResultsHeight, true)
                .environment(\.colorScheme, .light)
                .padding(16)
                .background(PagePaper(dark: false))
        )
        let darkPalette = SnapshotChrome(
            caption: "Cmd-K Jump to · dark",
            content: JumpPaletteView(palette: palette)
                .environment(\.rendersForSnapshot, true)
                .environment(\.snapshotReservesResultsHeight, true)
                .environment(\.colorScheme, .dark)
                .padding(16)
                .background(PagePaper(dark: true))
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
        try renderReservedJumpPalette(catalogue: catalogue, output: output)
        for hit in catalogue {
            fputs("\(hit.label)  p.\(hit.pageIndex + 1)  \(hit.firstLine)\n", stdout)
        }
    }

    /// Two hit counts, one chrome. A short query and a miss both keep the
    /// 420pt results frame, so the glass cannot grow or shrink with the list.
    /// The first row is the keyboard selection. The second row is the shared
    /// hover fill; ImageRenderer has no pointer, so the snapshot names that row.
    @MainActor
    private static func renderReservedJumpPalette(catalogue: [DocumentFind.Hit], output: URL) throws {
        guard JumpPaletteMetrics.resultsAreaHeight == 420 else {
            throw SnapshotError("reserved height is \(JumpPaletteMetrics.resultsAreaHeight), expected 420")
        }
        guard JumpPaletteMetrics.animatesResultsHeight == false else {
            throw SnapshotError("results height still animates")
        }
        guard JumpPaletteMetrics.rowHighlightOpacity == 0.14 else {
            throw SnapshotError("row highlight opacity changed")
        }
        let heights = [0, 1, catalogue.count].map { JumpPaletteMetrics.resultsFrameHeight(hitCount: $0) }
        guard Set(heights).count == 1, heights[0] == 420 else {
            throw SnapshotError("results frame follows the hit count: \(heights)")
        }
        guard JumpPaletteMetrics.rowIsHighlighted(isSelected: true, isHovered: false),
              JumpPaletteMetrics.rowIsHighlighted(isSelected: false, isHovered: true),
              !JumpPaletteMetrics.rowIsHighlighted(isSelected: false, isHovered: false) else {
            throw SnapshotError("selection and hover no longer share one highlight")
        }

        let matchedHits = DocumentFind.filterCatalogue(catalogue, query: "theorem")
        let matchedLabels = matchedHits.map(\.label)
        guard matchedLabels == [
            "Theorem 1.3.3",
            "Theorem 2.3.1 (Cauchy or Cauchy-Goursat Theorem)",
            "Theorem 3.5.27 (Residue theorem)",
            "Theorem 9",
            "Definition 3.2.1 (Homotopy Version of Cauchy's Theorem)",
        ] else {
            throw SnapshotError("unexpected theorem rows: \(matchedLabels)")
        }
        guard DocumentFind.filterCatalogue(catalogue, query: "zzzz").isEmpty else {
            throw SnapshotError("zzzz should miss every indexed statement")
        }

        let hovered = matchedHits[1]
        let matched = JumpPaletteModel()
        matched.showSnapshot(query: "theorem", hits: matchedHits, selection: 0)
        let missed = JumpPaletteModel()
        missed.showSnapshot(query: "zzzz", hits: [], selection: 0)

        let lightMatched = JumpPaletteCard(palette: matched, hoveredHitID: hovered.id, dark: false)
        let lightMissed = JumpPaletteCard(palette: missed, hoveredHitID: nil, dark: false)
        let darkMatched = JumpPaletteCard(palette: matched, hoveredHitID: hovered.id, dark: true)
        let darkMissed = JumpPaletteCard(palette: missed, hoveredHitID: nil, dark: true)

        let lightMatchedPNG = try renderedPNG(lightMatched)
        let lightMissedPNG = try renderedPNG(lightMissed)
        let darkMatchedPNG = try renderedPNG(darkMatched)
        let darkMissedPNG = try renderedPNG(darkMissed)
        let minimumHeight = Int(JumpPaletteMetrics.resultsAreaHeight * 2)
        guard lightMatchedPNG.pixelsHigh >= minimumHeight else {
            throw SnapshotError("theorem palette is \(lightMatchedPNG.pixelsHigh)px tall, under the 420pt results frame")
        }
        guard lightMatchedPNG.pixelsWide == lightMissedPNG.pixelsWide,
              lightMatchedPNG.pixelsHigh == lightMissedPNG.pixelsHigh else {
            throw SnapshotError("light chrome changed with hit count: \(lightMatchedPNG.pixelsWide)x\(lightMatchedPNG.pixelsHigh) vs \(lightMissedPNG.pixelsWide)x\(lightMissedPNG.pixelsHigh)")
        }
        guard darkMatchedPNG.pixelsWide == darkMissedPNG.pixelsWide,
              darkMatchedPNG.pixelsHigh == darkMissedPNG.pixelsHigh else {
            throw SnapshotError("dark chrome changed with hit count: \(darkMatchedPNG.pixelsWide)x\(darkMatchedPNG.pixelsHigh) vs \(darkMissedPNG.pixelsWide)x\(darkMissedPNG.pixelsHigh)")
        }

        let sheet = VStack(alignment: .leading, spacing: 28) {
            Text("Cmd-K Jump · results stay 420pt")
                .font(.caption)
                .foregroundStyle(.secondary)
            ReservedJumpPair(
                title: "theorem · selection and hover",
                emptyTitle: "no matches · same glass",
                matched: lightMatched,
                missed: lightMissed
            )
            ReservedJumpPair(
                title: "theorem · dark",
                emptyTitle: "no matches · dark",
                matched: darkMatched,
                missed: darkMissed
            )
        }
        .padding(28)
        .background(Color(white: 0.94))
        try writePNG(sheet, to: output.appendingPathComponent("cmd-k-jump.png"), minimumBytes: 20_000)
        fputs(
            "cmd-k reserved \(Int(JumpPaletteMetrics.resultsAreaHeight))pt  light \(lightMatchedPNG.pixelsWide)x\(lightMatchedPNG.pixelsHigh)  dark \(darkMatchedPNG.pixelsWide)x\(darkMatchedPNG.pixelsHigh)\n",
            stdout
        )
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

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            capsule
            if !hits.isEmpty {
                namedList
            }
        }
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

            Image(systemName: "chevron.up")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
            Image(systemName: "chevron.down")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.55), in: Capsule())
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
        .background(
            Color.white.opacity(0.45),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
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

/// One Cmd-K panel over the page. The frost stands in for Liquid Glass, which
/// ImageRenderer drops. The results frame is the reserved 420pt.
private struct JumpPaletteCard: View {
    var palette: JumpPaletteModel
    var hoveredHitID: String?
    var dark: Bool

    var body: some View {
        JumpPaletteView(palette: palette)
            .environment(\.rendersForSnapshot, true)
            .environment(\.snapshotReservesResultsHeight, true)
            .environment(\.snapshotHoveredHitID, hoveredHitID)
            .environment(\.colorScheme, dark ? .dark : .light)
            .padding(16)
            .background(PagePaper(dark: dark))
    }
}

private struct ReservedJumpPair<Matched: View, Missed: View>: View {
    var title: String
    var emptyTitle: String
    var matched: Matched
    var missed: Missed

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                matched
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(emptyTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                missed
            }
        }
    }
}

/// The page behind the palette. ImageRenderer cannot sample `glassEffect`,
/// so the snapshot frost is translucent and this paper colour shows through.
private struct PagePaper: View {
    var dark: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            (dark ? Color(white: 0.10) : Color(red: 0.98, green: 0.97, blue: 0.94))
            VStack(alignment: .leading, spacing: 7) {
                ForEach(0..<24, id: \.self) { index in
                    Capsule()
                        .fill((dark ? Color.white : Color.black).opacity(dark ? 0.16 : 0.08))
                        .frame(width: lineWidth(index), height: 5)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
        }
    }

    private func lineWidth(_ index: Int) -> CGFloat {
        let pattern: [CGFloat] = [210, 260, 170, 240, 120, 200, 250, 150]
        return pattern[index % pattern.count]
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
private func renderedPNG<V: View>(_ view: V) throws -> (data: Data, pixelsWide: Int, pixelsHigh: Int) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    renderer.isOpaque = true
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        throw SnapshotError("ImageRenderer produced no PNG")
    }
    return (png, rep.pixelsWide, rep.pixelsHigh)
}

@MainActor
private func writePNG<V: View>(_ view: V, to url: URL, minimumBytes: Int) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let png = try renderedPNG(view)
    guard png.data.count >= minimumBytes, png.pixelsWide > 40, png.pixelsHigh > 40 else {
        throw SnapshotError("PNG is \(png.data.count) bytes, \(png.pixelsWide)x\(png.pixelsHigh)")
    }
    try png.data.write(to: url)
    fputs("wrote \(url.path) (\(png.data.count) bytes, \(png.pixelsWide)x\(png.pixelsHigh))\n", stdout)
}
