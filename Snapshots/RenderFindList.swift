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
                .environment(\.snapshotCapsResultsHeight, true)
                .environment(\.colorScheme, .light)
                .padding(16)
                .background(PagePaper(dark: false))
        )
        let darkPalette = SnapshotChrome(
            caption: "Cmd-K Jump to · dark",
            content: JumpPaletteView(palette: palette)
                .environment(\.rendersForSnapshot, true)
                .environment(\.snapshotCapsResultsHeight, true)
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
        try renderAdaptiveJumpPalette(catalogue: catalogue, output: output)
        for hit in catalogue {
            fputs("\(hit.label)  p.\(hit.pageIndex + 1)  \(hit.firstLine)\n", stdout)
        }
    }

    /// Jerry’s miss (`asdfajs;lfas`) collapses under the field. A handful of
    /// rows stays under the cap. Two long lists share one 420pt results frame,
    /// so a keystroke that stays in that range does not move the glass.
    /// The first theorem row is the keyboard selection. The second row is the
    /// shared hover fill; ImageRenderer has no pointer, so the snapshot names it.
    @MainActor
    private static func renderAdaptiveJumpPalette(catalogue: [DocumentFind.Hit], output: URL) throws {
        guard JumpPaletteMetrics.maxResultsHeight == 420 else {
            throw SnapshotError("results cap is \(JumpPaletteMetrics.maxResultsHeight), expected 420")
        }
        guard JumpPaletteMetrics.resultsAreaHeight == JumpPaletteMetrics.maxResultsHeight else {
            throw SnapshotError("results cap and resultsAreaHeight diverged")
        }
        guard JumpPaletteMetrics.animatesResultsHeight == false else {
            throw SnapshotError("results height still animates")
        }
        guard JumpPaletteMetrics.rowHighlightOpacity == 0.14 else {
            throw SnapshotError("row highlight opacity changed")
        }
        let emptyHeight = JumpPaletteMetrics.resultsFrameHeight(hitCount: 0)
        let oneHeight = JumpPaletteMetrics.resultsFrameHeight(hitCount: 1)
        let fewHeight = JumpPaletteMetrics.resultsFrameHeight(hitCount: catalogue.count)
        guard emptyHeight < oneHeight, oneHeight < fewHeight, fewHeight < JumpPaletteMetrics.maxResultsHeight else {
            throw SnapshotError("short lists do not collapse under the cap: \(emptyHeight), \(oneHeight), \(fewHeight)")
        }
        guard !JumpPaletteMetrics.locksResultsHeight(hitCount: 0),
              !JumpPaletteMetrics.locksResultsHeight(hitCount: 1) else {
            throw SnapshotError("empty or one hit still locks the results frame")
        }
        let cappedCounts = [24, 40]
        let cappedHeights = cappedCounts.map { JumpPaletteMetrics.resultsFrameHeight(hitCount: $0) }
        guard Set(cappedHeights) == [JumpPaletteMetrics.maxResultsHeight],
              cappedCounts.allSatisfy({ JumpPaletteMetrics.locksResultsHeight(hitCount: $0) }) else {
            throw SnapshotError("capped lists do not share one height: \(cappedHeights)")
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
        let jerryQuery = "asdfajs;lfas"
        guard DocumentFind.filterCatalogue(catalogue, query: jerryQuery).isEmpty else {
            throw SnapshotError("\(jerryQuery) should miss every indexed statement")
        }
        guard DocumentFind.filterCatalogue(catalogue, query: "zzzz").isEmpty else {
            throw SnapshotError("zzzz should miss every indexed statement")
        }

        let hovered = matchedHits[1]
        let matched = JumpPaletteModel()
        matched.showSnapshot(query: "theorem", hits: matchedHits, selection: 0)
        let oneHit = JumpPaletteModel()
        oneHit.showSnapshot(query: "Lemma 2.4", hits: [matchedHits[0]], selection: 0)
        let missed = JumpPaletteModel()
        missed.showSnapshot(query: jerryQuery, hits: [], selection: 0)
        let cappedFew = JumpPaletteModel()
        cappedFew.showSnapshot(query: "theorem", hits: repeatedHits(catalogue, count: 24), selection: 0)
        let cappedMany = JumpPaletteModel()
        cappedMany.showSnapshot(query: "theorem", hits: repeatedHits(catalogue, count: 40), selection: 0)

        let lightMatched = JumpPaletteCard(palette: matched, hoveredHitID: hovered.id, dark: false)
        let lightOne = JumpPaletteCard(palette: oneHit, hoveredHitID: nil, dark: false)
        let lightMissed = JumpPaletteCard(palette: missed, hoveredHitID: nil, dark: false)
        let lightCappedFew = JumpPaletteCard(palette: cappedFew, hoveredHitID: nil, dark: false)
        let lightCappedMany = JumpPaletteCard(palette: cappedMany, hoveredHitID: nil, dark: false)
        let darkMatched = JumpPaletteCard(palette: matched, hoveredHitID: hovered.id, dark: true)
        let darkMissed = JumpPaletteCard(palette: missed, hoveredHitID: nil, dark: true)

        let lightMatchedPNG = try renderedPNG(lightMatched)
        let lightOnePNG = try renderedPNG(lightOne)
        let lightMissedPNG = try renderedPNG(lightMissed)
        let lightCappedFewPNG = try renderedPNG(lightCappedFew)
        let lightCappedManyPNG = try renderedPNG(lightCappedMany)
        let darkMatchedPNG = try renderedPNG(darkMatched)
        let darkMissedPNG = try renderedPNG(darkMissed)
        try assertCompactMiss(lightMissedPNG, beside: lightOnePNG, and: lightMatchedPNG, label: "light")
        try assertCompactMiss(darkMissedPNG, beside: lightOnePNG, and: darkMatchedPNG, label: "dark")
        let capFloor = Int(JumpPaletteMetrics.maxResultsHeight * 2)
        guard lightCappedFewPNG.pixelsHigh >= capFloor, lightCappedManyPNG.pixelsHigh >= capFloor else {
            throw SnapshotError("long list is under the 420pt cap: \(lightCappedFewPNG.pixelsHigh), \(lightCappedManyPNG.pixelsHigh)")
        }
        guard lightCappedFewPNG.pixelsHigh <= capFloor + 360,
              lightCappedManyPNG.pixelsHigh <= capFloor + 360 else {
            throw SnapshotError("long list grew past the cap: \(lightCappedFewPNG.pixelsHigh), \(lightCappedManyPNG.pixelsHigh)")
        }
        guard lightCappedFewPNG.pixelsWide == lightCappedManyPNG.pixelsWide,
              lightCappedFewPNG.pixelsHigh == lightCappedManyPNG.pixelsHigh else {
            throw SnapshotError("capped chrome jumped with hit count: \(lightCappedFewPNG.pixelsWide)x\(lightCappedFewPNG.pixelsHigh) vs \(lightCappedManyPNG.pixelsWide)x\(lightCappedManyPNG.pixelsHigh)")
        }
        guard lightCappedManyPNG.pixelsHigh > lightMatchedPNG.pixelsHigh else {
            throw SnapshotError("capped list is not taller than the theorem list")
        }

        let windowHeight: CGFloat = 760
        let inset = JumpPaletteMetrics.searchFieldTopInset(windowHeight: windowHeight)
        guard inset == (windowHeight - JumpPaletteMetrics.placementHeight) / 2 else {
            throw SnapshotError("search field inset follows the list: \(inset)")
        }
        let lightAnchoredLong = AnchoredJumpWindow(
            palette: cappedMany, hoveredHitID: nil, dark: false, windowHeight: windowHeight
        )
        let lightAnchoredMiss = AnchoredJumpWindow(
            palette: missed, hoveredHitID: nil, dark: false, windowHeight: windowHeight
        )
        let darkAnchoredLong = AnchoredJumpWindow(
            palette: cappedMany, hoveredHitID: nil, dark: true, windowHeight: windowHeight
        )
        let darkAnchoredMiss = AnchoredJumpWindow(
            palette: missed, hoveredHitID: nil, dark: true, windowHeight: windowHeight
        )
        let lightLongPNG = try renderedPNG(lightAnchoredLong)
        let lightMissWindowPNG = try renderedPNG(lightAnchoredMiss)
        let darkLongPNG = try renderedPNG(darkAnchoredLong)
        let darkMissWindowPNG = try renderedPNG(darkAnchoredMiss)
        try assertFieldStaysPut(lightLongPNG, lightMissWindowPNG, label: "light")
        try assertFieldStaysPut(darkLongPNG, darkMissWindowPNG, label: "dark")

        let sheet = VStack(alignment: .leading, spacing: 28) {
            Text("Cmd-K Jump · search field stays put, list grows down")
                .font(.caption)
                .foregroundStyle(.secondary)
            ReservedJumpPair(
                title: "40 hits · field top",
                emptyTitle: "asdfajs;lfas · same field top",
                matched: lightAnchoredLong,
                missed: lightAnchoredMiss
            )
            ReservedJumpPair(
                title: "40 hits · dark",
                emptyTitle: "asdfajs;lfas · dark",
                matched: darkAnchoredLong,
                missed: darkAnchoredMiss
            )
            ReservedJumpPair(
                title: "24 hits · capped",
                emptyTitle: "40 hits · same cap",
                matched: lightCappedFew,
                missed: lightCappedMany
            )
        }
        .padding(28)
        .background(Color(white: 0.94))
        try writePNG(sheet, to: output.appendingPathComponent("cmd-k-jump.png"), minimumBytes: 20_000)
        fputs(
            "cmd-k cap \(Int(JumpPaletteMetrics.maxResultsHeight))pt  inset \(Int(inset))pt  miss \(lightMissedPNG.pixelsWide)x\(lightMissedPNG.pixelsHigh)  one \(lightOnePNG.pixelsWide)x\(lightOnePNG.pixelsHigh)  theorem \(lightMatchedPNG.pixelsWide)x\(lightMatchedPNG.pixelsHigh)  capped \(lightCappedManyPNG.pixelsWide)x\(lightCappedManyPNG.pixelsHigh)  field \(lightLongPNG.pixelsWide)x\(lightLongPNG.pixelsHigh)\n",
            stdout
        )
    }

    /// The red guide sits on the search field. A long list and a miss share
    /// that row. Further down, the miss is page again and the long list is not.
    private static func assertFieldStaysPut(
        _ long: (data: Data, pixelsWide: Int, pixelsHigh: Int),
        _ miss: (data: Data, pixelsWide: Int, pixelsHigh: Int),
        label: String
    ) throws {
        guard long.pixelsWide == miss.pixelsWide, long.pixelsHigh == miss.pixelsHigh else {
            throw SnapshotError("\(label) windows differ: \(long.pixelsWide)x\(long.pixelsHigh) vs \(miss.pixelsWide)x\(miss.pixelsHigh)")
        }
        let longGuide = try guideRow(in: long.data)
        let missGuide = try guideRow(in: miss.data)
        guard abs(longGuide - missGuide) <= 1 else {
            throw SnapshotError("\(label) search field moved: long \(longGuide) miss \(missGuide)")
        }
        let downward = longGuide < long.pixelsHigh / 2
        let below = downward ? longGuide + 440 : longGuide - 440
        guard below > 0, below < long.pixelsHigh else {
            throw SnapshotError("\(label) field guide \(longGuide) leaves no room to sample the list")
        }
        let longIsPage = try isPagePixel(in: long.data, x: long.pixelsWide / 2, y: below)
        let missIsPage = try isPagePixel(in: miss.data, x: miss.pixelsWide / 2, y: below)
        guard missIsPage else {
            throw SnapshotError("\(label) miss is still glass \(below)px under the field")
        }
        guard !longIsPage else {
            throw SnapshotError("\(label) long list collapsed where it should still be glass")
        }
    }

    private static func guideRow(in data: Data) throws -> Int {
        guard let rep = NSBitmapImageRep(data: data) else {
            throw SnapshotError("field guide is not a bitmap")
        }
        let x = rep.pixelsWide / 2
        for y in 0..<rep.pixelsHigh {
            guard let color = rep.colorAt(x: x, y: y) else { continue }
            let resolved = color.usingColorSpace(.sRGB) ?? color
            if resolved.redComponent > 0.7, resolved.greenComponent < 0.35, resolved.blueComponent < 0.35 {
                return y
            }
        }
        throw SnapshotError("search-field guide was not drawn")
    }

    /// Flat window colour behind the palette. Glass and the red guide are not this.
    private static func isPagePixel(in data: Data, x: Int, y: Int) throws -> Bool {
        guard let rep = NSBitmapImageRep(data: data),
              let raw = rep.colorAt(x: x, y: y) else {
            throw SnapshotError("could not sample \(x),\(y)")
        }
        let color = raw.usingColorSpace(.sRGB) ?? raw
        // Same flats as AnchoredJumpWindow. Frost blends toward white and
        // does not land on these.
        let page = (red: CGFloat(0.69), green: CGFloat(0.78), blue: CGFloat(0.88))
        let dark = (red: CGFloat(0.12), green: CGFloat(0.12), blue: CGFloat(0.12))
        func near(_ sample: (red: CGFloat, green: CGFloat, blue: CGFloat)) -> Bool {
            abs(color.redComponent - sample.red) < 0.05
                && abs(color.greenComponent - sample.green) < 0.05
                && abs(color.blueComponent - sample.blue) < 0.05
        }
        return near(page) || near(dark)
    }

    /// A miss sits under the field. One hit and a short theorem list are taller
    /// than that miss and still well under a panel whose results area is 420pt.
    private static func assertCompactMiss(
        _ miss: (data: Data, pixelsWide: Int, pixelsHigh: Int),
        beside one: (data: Data, pixelsWide: Int, pixelsHigh: Int),
        and few: (data: Data, pixelsWide: Int, pixelsHigh: Int),
        label: String
    ) throws {
        guard miss.pixelsHigh < 520 else {
            throw SnapshotError("\(label) miss is \(miss.pixelsHigh)px tall, still a cavern")
        }
        guard miss.pixelsHigh < one.pixelsHigh, one.pixelsHigh < few.pixelsHigh else {
            throw SnapshotError("\(label) height does not follow the hit count: miss \(miss.pixelsHigh), one \(one.pixelsHigh), few \(few.pixelsHigh)")
        }
        // A results area held at 420pt makes this card about 960px. Five rows
        // sit well under that; the miss check above is the cavern guard.
        guard few.pixelsHigh < 900 else {
            throw SnapshotError("\(label) theorem list is \(few.pixelsHigh)px, already at the cap")
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

    /// Copies catalogue rows until `count`, with distinct ids so the list can
    /// paint a capped panel. Order follows the catalogue, then repeats.
    private static func repeatedHits(_ hits: [DocumentFind.Hit], count: Int) -> [DocumentFind.Hit] {
        guard !hits.isEmpty else { return [] }
        return (0..<count).map { index in
            var hit = hits[index % hits.count]
            hit.id = "\(hit.id)#\(index)"
            return hit
        }
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

/// The page column with the field pinned. The red guide is the field’s top
/// edge; a miss and a long list share it, and only the list under it changes.
private struct AnchoredJumpWindow: View {
    var palette: JumpPaletteModel
    var hoveredHitID: String?
    var dark: Bool
    var windowHeight: CGFloat

    var body: some View {
        let inset = JumpPaletteMetrics.searchFieldTopInset(windowHeight: windowHeight)
        JumpPaletteView(palette: palette)
            .environment(\.rendersForSnapshot, true)
            .environment(\.snapshotCapsResultsHeight, true)
            .environment(\.snapshotHoveredHitID, hoveredHitID)
            .environment(\.colorScheme, dark ? .dark : .light)
            .padding(.top, inset)
            .frame(width: 440, height: windowHeight, alignment: .top)
            .background(dark ? Color(white: 0.12) : Color(red: 0.69, green: 0.78, blue: 0.88))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.red)
                    .frame(maxWidth: .infinity)
                    .frame(height: 2)
                    .offset(y: inset - 20)
            }
            .clipped()
    }
}

/// One Cmd-K panel over the page. The frost stands in for Liquid Glass, which
/// ImageRenderer drops. A long list is clipped at the 420pt cap; a miss is not.
private struct JumpPaletteCard: View {
    var palette: JumpPaletteModel
    var hoveredHitID: String?
    var dark: Bool

    var body: some View {
        JumpPaletteView(palette: palette)
            .environment(\.rendersForSnapshot, true)
            .environment(\.snapshotCapsResultsHeight, true)
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
