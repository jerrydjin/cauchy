import Foundation
import PDFKit

struct DocumentReferenceIndexSnapshot: Sendable {
    let entries: [ReferenceKey: IndexedReference]
    let pageCount: Int
}

final class DocumentReferenceIndex: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [ReferenceKey: IndexedReference] = [:]

    var entryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    func lookup(_ reference: DetectedReference) -> IndexedReference? {
        lock.lock()
        defer { lock.unlock() }
        return entries[reference.key]
    }

    func replace(with snapshot: DocumentReferenceIndexSnapshot) {
        lock.lock()
        entries = snapshot.entries
        lock.unlock()
    }

    func clear() {
        lock.lock()
        entries = [:]
        lock.unlock()
    }
}
