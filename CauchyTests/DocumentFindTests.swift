import XCTest
@testable import Cauchy

final class DocumentFindTests: XCTestCase {
    func testShortLemmaNumberListsEveryExtensionAndJumpsOnlyForOne() {
        let entries = [
            entry(.lemma, "2", "Let G be trivial."),
            entry(.lemma, "2.1", "Let G be finite."),
            entry(.lemma, "2.2", "Let G be abelian."),
            entry(.lemma, "20", "This is a different lemma."),
            entry(.lemma, "12", "Twelve is not an extension of two."),
            entry(.theorem, "2.1", "A theorem numbered 2.1."),
        ]
        let several = DocumentFind.search(query: "Lemma 2", entries: entries, sections: [])
        XCTAssertEqual(several.hits.map(\.label), ["Lemma 2", "Lemma 2.1", "Lemma 2.2"])
        XCTAssertEqual(several.hits.map(\.firstLine), [
            "Let G be trivial.",
            "Let G be finite.",
            "Let G be abelian.",
        ])
        XCTAssertFalse(several.jumpsImmediately)
        XCTAssertNil(several.message)
        XCTAssertTrue(several.suppressesTextSearch)

        let one = DocumentFind.search(query: "Lemma 2.2", entries: entries, sections: [])
        XCTAssertEqual(one.hits.map(\.label), ["Lemma 2.2"])
        XCTAssertTrue(one.jumpsImmediately)

        let missing = DocumentFind.search(query: "Lemma 9", entries: entries, sections: [])
        XCTAssertEqual(missing.hits, [])
        XCTAssertEqual(missing.message, "No \"Lemma 9\" in this document")
        XCTAssertTrue(missing.suppressesTextSearch)
    }

    func testPrintedNameAndGroupedOrder() {
        let entries = [
            entry(.lemma, "2.4", "Every chain has an upper bound.", name: "Zorn"),
            entry(.theorem, "1", "A named theorem.", name: "Zorn"),
            entry(.definition, "3", "A compact space.", name: "Compactness"),
        ]
        let zorn = DocumentFind.search(query: "Zorn", entries: entries, sections: [])
        XCTAssertEqual(zorn.hits.map(\.group), ["Theorems", "Lemmas"])
        XCTAssertEqual(zorn.hits.map(\.label), ["Theorem 1 (Zorn)", "Lemma 2.4 (Zorn)"])
        XCTAssertFalse(zorn.suppressesTextSearch)
        XCTAssertNil(zorn.message)

        let exact = DocumentFind.search(query: "Lemma 2.4 (Zorn)", entries: entries, sections: [])
        XCTAssertEqual(exact.hits.map(\.label), ["Lemma 2.4 (Zorn)"])
        XCTAssertTrue(exact.jumpsImmediately)

        let plain = DocumentFind.search(query: "continuous", entries: entries, sections: [])
        XCTAssertTrue(plain.hits.isEmpty)
        XCTAssertFalse(plain.suppressesTextSearch)
        XCTAssertNil(plain.message)
    }

    func testSectionHeadingsUseThePrintedNumber() {
        let pages = [
            "Contents\n1. Introduction .... 1\n2. Groups .... 4\n2.1 Actions .... 6\n3. Rings .... 9\nIndex .... 12\n",
            "1. Introduction\nThe notes begin here.",
            "2 Integrals appear here.\n2.1. Actions of a group.\n",
        ]
        let sections = DocumentFind.sections(in: pages)
        XCTAssertEqual(sections.map(\.number), ["1", "2.1"])
        XCTAssertEqual(sections.map(\.title), ["Introduction", "Actions of a group"])
        XCTAssertEqual(sections.map(\.pageIndex), [1, 2])

        let found = DocumentFind.search(query: "Section 2", entries: [], sections: sections)
        XCTAssertEqual(found.hits.map(\.label), ["Section 2.1"])
        XCTAssertEqual(found.hits.map(\.firstLine), ["Actions of a group"])
        XCTAssertEqual(found.hits.map(\.pageIndex), [2])

        let missing = DocumentFind.search(query: "Section 9", entries: [], sections: sections)
        XCTAssertEqual(missing.message, "No \"Section 9\" in this document")
        XCTAssertTrue(missing.hits.isEmpty)
    }

    func testTruncatedPreviewEndsWithAnEllipsis() {
        let body = "A finite group of odd order is solvable when every proper sample subgroup is already known to be solvable."
        let line = DocumentFind.firstLine(of: body)
        XCTAssertTrue(line.hasSuffix("…"))
        XCTAssertFalse(line.hasSuffix("..."))
        XCTAssertLessThanOrEqual(line.count, DocumentFind.previewCharacterLimit)
        XCTAssertGreaterThan(body.count, DocumentFind.previewCharacterLimit)
    }

    func testRepeatedLabelIsNotShownAndARealNameIs() {
        XCTAssertEqual(
            DocumentFind.displayNames(kind: .theorem, number: "1.3.3", name: "Theorem 1.3.3"),
            []
        )
        XCTAssertEqual(
            DocumentFind.displayNames(kind: .theorem, number: "1.3.3", name: "theorem 1.3.3"),
            []
        )
        XCTAssertEqual(
            DocumentFind.displayNames(kind: .theorem, number: "1.3.3", name: "Thm. 1.3.3"),
            []
        )
        XCTAssertEqual(
            DocumentFind.displayNames(kind: .theorem, number: "1.3.3", name: "1.3.3"),
            []
        )
        XCTAssertEqual(
            DocumentFind.displayNames(kind: .theorem, number: "1.3.3", name: "Theorem 1.3.3 (Theorem 1.3.3)"),
            []
        )
        XCTAssertEqual(
            DocumentFind.displayNames(kind: .theorem, number: "3.5.27", name: "Residue theorem"),
            ["Residue theorem", "Residue"]
        )
        XCTAssertEqual(
            DocumentFind.displayNames(kind: .theorem, number: "1.3.3", name: "Theorem 1.3.3 (Residue theorem)"),
            ["Residue theorem", "Residue"]
        )

        let cauchy = DocumentFind.displayNames(
            kind: .theorem,
            number: "2.3.1",
            name: "Cauchy or Cauchy-Goursat Theorem"
        )
        XCTAssertEqual(
            Array(cauchy.prefix(3)),
            ["Cauchy or Cauchy-Goursat Theorem", "Cauchy-Goursat Theorem", "Cauchy"]
        )

        let entries = [
            entry(.theorem, "1.3.3", "Let U be open.", name: "Theorem 1.3.3"),
            entry(.theorem, "3.5.27", "Suppose that U is open.", name: "Residue theorem"),
            entry(.theorem, "2.3.1", "Let U be a domain.", name: "Cauchy or Cauchy-Goursat Theorem"),
        ]
        let repeated = DocumentFind.search(query: "Theorem 1.3.3", entries: entries, sections: [])
        XCTAssertEqual(repeated.hits.map(\.label), ["Theorem 1.3.3"])
        XCTAssertEqual(repeated.hits.map(\.title), ["Theorem 1.3.3"])
        XCTAssertTrue(repeated.hits[0].nameCandidates.isEmpty)

        let residue = DocumentFind.search(query: "Theorem 3.5.27", entries: entries, sections: [])
        XCTAssertEqual(residue.hits.map(\.label), ["Theorem 3.5.27 (Residue theorem)"])
        XCTAssertEqual(residue.hits.map(\.anchor), ["Theorem 3.5.27"])
    }

    func testCutOffNameIsHiddenFromTheJumpRow() {
        let cutOff = entry(
            .definition,
            "3.2.1",
            "Two cycles are homologous when their difference is a boundary.",
            name: "Homotopy Version of"
        )
        let hits = DocumentFind.jumpHits(query: "", entries: [cutOff], sections: [])
        XCTAssertEqual(hits.map(\.title), ["Definition 3.2.1"])
        XCTAssertEqual(hits.map(\.label), ["Definition 3.2.1 (Homotopy Version of)"])
        XCTAssertEqual(hits.map(\.jumpName), ["Homotopy Version of"])
        XCTAssertFalse(hits[0].nameCandidates.isEmpty)
        XCTAssertTrue(DocumentFind.namesForDisplay(hits[0].nameCandidates).names.isEmpty)

        let found = DocumentFind.jumpHits(query: "homotopy", entries: [cutOff], sections: [])
        XCTAssertEqual(found.map(\.title), ["Definition 3.2.1"])
        XCTAssertEqual(found.map(\.jumpName), ["Homotopy Version of"])

        for word in ["of", "the", "a", "an", "and", "for", "to", "in", "on", "with"] {
            let names = DocumentFind.displayNames(
                kind: .definition,
                number: "3.2.1",
                name: "Homotopy Version \(word)"
            )
            XCTAssertEqual(
                DocumentFind.namesForDisplay(names).names,
                [],
                "a name ending in \(word) stays indexed and is left off the row"
            )
        }

        let full = DocumentFind.displayNames(
            kind: .definition,
            number: "3.2.1",
            name: "Homotopy Version of Cauchy's Theorem"
        )
        XCTAssertEqual(full.first, "Homotopy Version of Cauchy's Theorem")
        let visible = DocumentFind.namesForDisplay(full)
        XCTAssertEqual(visible.names, [
            "Homotopy Version of Cauchy's Theorem",
            "Homotopy Version of Cauchy's",
        ])
        XCTAssertTrue(visible.stoppedBeforeCutOff)
        XCTAssertFalse(visible.names.contains("Homotopy Version of"))

        let residue = DocumentFind.namesForDisplay(
            DocumentFind.displayNames(kind: .theorem, number: "3.5.27", name: "Residue theorem")
        )
        XCTAssertEqual(residue.names, ["Residue theorem", "Residue"])
        XCTAssertFalse(residue.stoppedBeforeCutOff)
    }

    func testSpacingAcuteBeforeTheVowelDisplaysAsRouche() {
        let broken = "Rouch\u{00B4}e"
        let indexed = DocumentFind.displayNames(kind: .theorem, number: "3.6.3", name: broken)
        XCTAssertEqual(indexed, [broken], "the indexed name stays the text-layer spelling")
        XCTAssertEqual(DocumentFind.namesForDisplay(indexed).names, ["Rouché"])

        let statement = entry(
            .theorem,
            "3.6.3",
            "Suppose that f and g are holomorphic functions on an open set.",
            name: broken
        )
        let hits = DocumentFind.jumpHits(query: "holomorphic", entries: [statement], sections: [])
        XCTAssertEqual(hits.map(\.title), ["Theorem 3.6.3"])
        XCTAssertEqual(hits.map(\.jumpName), [broken])
        XCTAssertEqual(hits.map(\.label), ["Theorem 3.6.3 (\(broken))"])
        XCTAssertEqual(DocumentFind.namesForDisplay(hits[0].nameCandidates).names, ["Rouché"])

        XCTAssertEqual(
            DocumentFind.namesForDisplay(
                DocumentFind.displayNames(kind: .theorem, number: "1", name: "Poincar\u{00B4}e")
            ).names,
            ["Poincaré"]
        )
        XCTAssertEqual(
            DocumentFind.namesForDisplay(
                DocumentFind.displayNames(kind: .theorem, number: "1", name: "G\u{00A8}odel")
            ).names,
            ["Gödel"]
        )
        XCTAssertEqual(
            DocumentFind.namesForDisplay(
                DocumentFind.displayNames(kind: .theorem, number: "1", name: "Rouch\u{02CA}e")
            ).names,
            ["Rouché"]
        )
        XCTAssertEqual(
            DocumentFind.namesForDisplay(
                DocumentFind.displayNames(kind: .theorem, number: "3.6.3", name: "Rouché")
            ).names,
            ["Rouché"]
        )
        XCTAssertEqual(
            DocumentFind.namesForDisplay(
                DocumentFind.displayNames(kind: .theorem, number: "3.6.6", name: "Open mapping theorem")
            ).names.first,
            "Open mapping theorem"
        )
        let withTheorem = DocumentFind.namesForDisplay(
            DocumentFind.displayNames(kind: .theorem, number: "3.6.3", name: "Rouch\u{00B4}e's theorem")
        )
        XCTAssertEqual(withTheorem.names, ["Rouché's theorem", "Rouché's"])
    }

    func testPreviewConvertsTeXAndSkipsUnreadableLines() {
        XCTAssertEqual(
            DocumentFind.firstLine(of: "Let U $\\subset C$ be open and $\\gamma \\in U$."),
            "Let U ⊂ C be open and γ ∈ U."
        )
        XCTAssertEqual(
            DocumentFind.firstLine(of: "Let $f\\left(z\\right)$ be holomorphic."),
            "Let f(z) be holomorphic."
        )
        XCTAssertEqual(
            DocumentFind.firstLine(of: "Let the vector $\\boldsymbol{v}$ be given."),
            "Let the vector v be given."
        )
        XCTAssertEqual(
            DocumentFind.firstLine(of: "$$\nSuppose that U is an open set."),
            "Suppose that U is an open set."
        )
        XCTAssertEqual(
            DocumentFind.firstLine(of: "f(z)dz= F($\u{8}oldsymbol{\nLet f be holomorphic on U."),
            "Let f be holomorphic on U."
        )
        XCTAssertEqual(DocumentFind.firstLine(of: "$$"), "")
        XCTAssertEqual(DocumentFind.firstLine(of: "{"), "")
        XCTAssertEqual(DocumentFind.firstLine(of: "$oldsymbol{"), "")
        XCTAssertEqual(
            DocumentFind.firstLine(of: "$$", sourceExcerpt: "Suppose that U is an open set in C."),
            "Suppose that U is an open set in C."
        )
        XCTAssertEqual(
            DocumentFind.firstLine(of: "Let G be trivial.", sourceExcerpt: "A different later line."),
            "Let G be trivial."
        )
        XCTAssertFalse(DocumentFind.firstLine(of: "$$\\gamma1\\ f\\left(z\\right)dz=").contains("$"))
        XCTAssertFalse(DocumentFind.firstLine(of: "$$\\gamma1\\ f\\left(z\\right)dz=").contains("{"))
        XCTAssertEqual(
            DocumentFind.firstLine(of: "$$\\gamma1\\ f\\left(z\\right)dz="),
            "γ1 f(z)dz="
        )
    }

    func testJumpListFiltersByKindNumberAndNameWithoutChangingNumberSearch() {
        let entries = [
            entry(.lemma, "2", "Let G be trivial."),
            entry(.lemma, "2.1", "Let G be finite."),
            entry(.lemma, "20", "This is a different lemma."),
            entry(.lemma, "2.4", "Every chain has an upper bound.", name: "Zorn"),
            entry(.theorem, "1.2.7", "A numbered theorem.", name: "Residue theorem"),
            entry(.theorem, "1.2.70", "Not an extension of 1.2.7."),
            entry(.theorem, "1.3.3", "Let U be open.", name: "Theorem 1.3.3"),
            entry(.definition, "3", "A compact space.", name: "Compactness"),
        ]
        let sections = [
            DocumentFind.Section(number: "1.2", title: "Actions of a group", pageIndex: 4, anchor: "1.2. Actions"),
        ]

        let all = DocumentFind.jumpHits(query: "", entries: entries, sections: sections)
        XCTAssertEqual(all.map(\.group), [
            "Theorems", "Theorems", "Theorems",
            "Lemmas", "Lemmas", "Lemmas", "Lemmas",
            "Definitions",
            "Sections",
        ])
        XCTAssertEqual(all.map(\.label), [
            "Theorem 1.2.7 (Residue theorem)",
            "Theorem 1.2.70",
            "Theorem 1.3.3",
            "Lemma 2",
            "Lemma 2.1",
            "Lemma 2.4 (Zorn)",
            "Lemma 20",
            "Definition 3 (Compactness)",
            "Section 1.2",
        ])

        let numbered = DocumentFind.jumpHits(query: "Lemma 2", entries: entries, sections: sections)
        let searched = DocumentFind.search(query: "Lemma 2", entries: entries, sections: sections)
        XCTAssertEqual(numbered, searched.hits)
        XCTAssertEqual(numbered.map(\.label), ["Lemma 2", "Lemma 2.1", "Lemma 2.4 (Zorn)"])
        XCTAssertFalse(numbered.contains { $0.number == "20" })

        let theorems = DocumentFind.jumpHits(query: "theorem", entries: entries, sections: sections)
        XCTAssertEqual(theorems.map(\.number), ["1.2.7", "1.2.70", "1.3.3"])
        let namedOnly = DocumentFind.search(query: "theorem", entries: entries, sections: sections)
        XCTAssertFalse(namedOnly.hits.contains { $0.number == "1.2.70" })

        let plural = DocumentFind.jumpHits(query: "theorems", entries: entries, sections: sections)
        XCTAssertEqual(plural.map(\.number), theorems.map(\.number))

        XCTAssertEqual(
            DocumentFind.jumpHits(query: "zorn", entries: entries, sections: sections).map(\.label),
            ["Lemma 2.4 (Zorn)"]
        )
        XCTAssertEqual(
            DocumentFind.jumpHits(query: "1.2.7", entries: entries, sections: sections).map(\.number),
            ["1.2.7"]
        )
        XCTAssertEqual(
            DocumentFind.jumpHits(query: "section", entries: entries, sections: sections).map(\.label),
            ["Section 1.2"]
        )
        XCTAssertEqual(
            DocumentFind.jumpHits(query: "actions", entries: entries, sections: sections).map(\.label),
            ["Section 1.2"]
        )
    }

    func testJumpQueryMatchesThePreviewWhenTheLabelAndNameDoNot() {
        let theorem = entry(
            .theorem,
            "1.3.3",
            "Let U be open and suppose that f is holomorphic.",
            name: "Theorem 1.3.3"
        )
        let lemma = entry(
            .lemma,
            "4",
            "Every holomorphic function on the disk is analytic."
        )
        let unrelated = entry(.lemma, "2", "Let G be trivial.", name: "Zorn")

        let found = DocumentFind.jumpHits(
            query: "holomorphic",
            entries: [unrelated, lemma, theorem],
            sections: []
        )
        XCTAssertEqual(found.map(\.group), ["Theorems", "Lemmas"])
        XCTAssertEqual(found.map(\.number), ["1.3.3", "4"])
        XCTAssertFalse(found[0].label.localizedCaseInsensitiveContains("holomorphic"))
        XCTAssertFalse(found[0].jumpName.localizedCaseInsensitiveContains("holomorphic"))
        XCTAssertTrue(found[0].firstLine.localizedCaseInsensitiveContains("holomorphic"))
        XCTAssertFalse(found.contains { $0.number == "2" })

        let upper = DocumentFind.jumpHits(query: "HOLOMORPHIC", entries: [theorem], sections: [])
        XCTAssertEqual(upper.map(\.number), ["1.3.3"])
        let partial = DocumentFind.jumpHits(query: "holo", entries: [theorem], sections: [])
        XCTAssertEqual(partial.map(\.number), ["1.3.3"])

        // The word sits past the one-line preview, so it is not a match.
        let hiddenBody = String(repeating: "alpha ", count: 30) + "quasiconformal"
        let hidden = entry(.theorem, "8", hiddenBody, name: "Theorem 8")
        let preview = DocumentFind.firstLine(of: hiddenBody)
        XCTAssertFalse(preview.localizedCaseInsensitiveContains("quasiconformal"))
        XCTAssertTrue(
            DocumentFind.jumpHits(query: "quasiconformal", entries: [hidden], sections: []).isEmpty
        )
    }

    func testPlainFindCountSaysMatchesInTheText() {
        XCTAssertEqual(DocumentFind.textMatchLabel(count: 232, isSearching: false), "232 matches in the text")
        XCTAssertEqual(DocumentFind.textMatchLabel(count: 1, isSearching: false), "1 match in the text")
        XCTAssertEqual(DocumentFind.textMatchLabel(count: 0, isSearching: false), "Not found")
        XCTAssertEqual(DocumentFind.textMatchLabel(count: 232, isSearching: true), "Searching…")
    }

    @MainActor
    func testJumpPaletteSelectsTheTopHitUntilAnArrowMovesIt() {
        let hits = DocumentFind.jumpHits(
            query: "",
            entries: [
                entry(.theorem, "1", "First."),
                entry(.lemma, "2", "Second."),
            ],
            sections: []
        )
        let palette = JumpPaletteModel()
        palette.showSnapshot(query: "", hits: hits)
        XCTAssertEqual(palette.selection, 0)
        XCTAssertEqual(palette.hits[palette.selection].title, "Theorem 1")
        palette.move(1)
        XCTAssertEqual(palette.hits[palette.selection].title, "Lemma 2")
        palette.move(1)
        XCTAssertEqual(palette.hits[palette.selection].title, "Lemma 2")
        palette.move(-1)
        palette.move(-1)
        XCTAssertEqual(palette.selection, 0)
    }

    @MainActor
    func testJumpPaletteQueryMatchingThePreviewKeepsArrowSelection() {
        let entries = [
            entry(.theorem, "1.3.3", "Let f be holomorphic.", name: "Theorem 1.3.3"),
            entry(.lemma, "2", "Let G be trivial.", name: "Zorn"),
        ]
        let palette = JumpPaletteModel()
        palette.source = {
            DocumentFind.Source(entries: entries, pages: [], catalogueID: 1)
        }
        palette.present()
        XCTAssertEqual(palette.hits.map(\.title), ["Theorem 1.3.3", "Lemma 2"])
        palette.query = "holomorphic"
        XCTAssertEqual(palette.hits.map(\.title), ["Theorem 1.3.3"])
        XCTAssertEqual(palette.selection, 0)
        palette.query = ""
        palette.move(1)
        XCTAssertEqual(palette.hits[palette.selection].title, "Lemma 2")
        palette.move(1)
        XCTAssertEqual(palette.selection, 1)
        palette.move(-1)
        XCTAssertEqual(palette.selection, 0)
    }

    func testTextLayerRepairTable() {
        XCTAssertEqual(TextLayerRepairs.table.map(\.broken), ["7→", #"∈(?=\S)"#])
        XCTAssertEqual(TextLayerRepairs.apply("7→"), "↦")
        XCTAssertEqual(TextLayerRepairs.apply("keep 7→ here"), "keep ↦ here")
        XCTAssertEqual(TextLayerRepairs.apply("x∈Y"), "x∈ Y")
        XCTAssertEqual(TextLayerRepairs.apply("x∈ Y"), "x∈ Y")
        XCTAssertEqual(TextLayerRepairs.apply("a∈b and c∈d"), "a∈ b and c∈ d")
        XCTAssertEqual(
            DocumentFind.firstLine(of: "The assignment f 7→ g stays inside x∈Y."),
            "The assignment f ↦ g stays inside x∈ Y."
        )
    }

    @MainActor
    func testCitedLookupReturnsTheFullNumberForAShortQuery() {
        let index = DocumentReferenceIndex()
        let entries = [
            ReferenceKey(kind: .lemma, number: "2.1"): indexed(.lemma, "2.1", "Let G be finite."),
            ReferenceKey(kind: .lemma, number: "2.2"): indexed(.lemma, "2.2", "Let G be abelian."),
            ReferenceKey(kind: .lemma, number: "4"): indexed(.lemma, "4", "Exactly four."),
            ReferenceKey(kind: .lemma, number: "4.1"): indexed(.lemma, "4.1", "A child of four."),
        ]
        index.replace(with: DocumentReferenceIndexSnapshot(entries: entries, pageCount: 3))

        let shortened = index.statements(citedIn: ["Lemma 2"])
        XCTAssertEqual(shortened.map(\.reference.number), ["2.1", "2.2"])

        let exact = index.statements(citedIn: ["Lemma 4"])
        XCTAssertTrue(exact.contains { $0.reference.number == "4" })
        XCTAssertFalse(exact.contains { $0.reference.number == "12" })
    }

    private func entry(
        _ kind: ReferenceKind,
        _ number: String,
        _ body: String,
        name: String? = nil
    ) -> DocumentFind.Entry {
        DocumentFind.Entry(
            kind: kind,
            number: number,
            name: name,
            body: body,
            pageIndex: 3,
            anchor: "\(kind.displayName) \(number)"
        )
    }

    private func indexed(_ kind: ReferenceKind, _ number: String, _ body: String) -> IndexedReference {
        IndexedReference(
            reference: DetectedReference(kind: kind, number: number),
            formattedBody: body,
            pageIndex: 1,
            contentOrigin: .sourceFallback
        )
    }
}
