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
