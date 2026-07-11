import Foundation
import PDFKit

struct DocumentReferenceIndexSnapshot: Sendable {
    let entries: [ReferenceKey: IndexedReference]
    let pageCount: Int
}

/// Lookup table for indexed references. Built off-main by
/// LLMReferenceIndexBuilder (which hands over an immutable snapshot), but only
/// ever read and mutated on the main actor (WorkspaceViewModel, PDFCanvasView
/// hover detection).
@MainActor
final class DocumentReferenceIndex {
    private var entries: [ReferenceKey: IndexedReference] = [:]

    func lookup(_ reference: DetectedReference) -> IndexedReference? {
        entries[reference.key]
    }

    func replace(with snapshot: DocumentReferenceIndexSnapshot) {
        entries = snapshot.entries
    }

    func clear() {
        entries = [:]
    }
}
