import CryptoKit
import Foundation

struct PersistedReferenceIndex: Codable, Sendable {
    static let schemaVersion = 2

    let schemaVersion: Int
    let documentFingerprint: String
    let builtAt: Date
    let entries: [PersistedReferenceEntry]

    init(documentFingerprint: String, builtAt: Date, entries: [ReferenceKey: IndexedReference]) {
        self.schemaVersion = Self.schemaVersion
        self.documentFingerprint = documentFingerprint
        self.builtAt = builtAt
        self.entries = entries.map { key, value in
            PersistedReferenceEntry(
                kind: key.kind.rawValue,
                number: key.number,
                formattedBody: value.formattedBody,
                pageIndex: value.pageIndex
            )
        }
    }

    func asSnapshot(pageCount: Int) -> DocumentReferenceIndexSnapshot {
        var merged: [ReferenceKey: IndexedReference] = [:]
        for entry in entries {
            guard let kind = ReferenceKind(rawValue: entry.kind) else { continue }
            let key = ReferenceKey(kind: kind, number: entry.number)
            let indexed = IndexedReference(
                reference: DetectedReference(kind: kind, number: entry.number),
                formattedBody: entry.formattedBody,
                pageIndex: entry.pageIndex
            )
            if let existing = merged[key] {
                if indexed.formattedBody.count > existing.formattedBody.count {
                    merged[key] = indexed
                }
            } else {
                merged[key] = indexed
            }
        }
        return DocumentReferenceIndexSnapshot(entries: merged, pageCount: pageCount)
    }
}

struct PersistedReferenceEntry: Codable, Sendable, Equatable {
    let kind: String
    let number: String
    let formattedBody: String
    let pageIndex: Int
}

enum ReferenceIndexCacheStore {
    private static let indexDirectoryName = "reference-index"

    static func fingerprint(for documentURL: URL) throws -> String {
        // Stream the file into the hasher: same digest as hashing Data(contentsOf:)
        // in one shot, without holding a potentially huge PDF in memory.
        let handle = try FileHandle(forReadingFrom: documentURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return "\(hash)-v\(PersistedReferenceIndex.schemaVersion)"
    }

    static func load(fingerprint: String) throws -> PersistedReferenceIndex? {
        let url = cacheFileURL(for: fingerprint)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let persisted = try decoder.decode(PersistedReferenceIndex.self, from: data)
        guard persisted.schemaVersion == PersistedReferenceIndex.schemaVersion else { return nil }
        guard persisted.documentFingerprint == fingerprint else { return nil }
        return persisted
    }

    static func save(_ index: PersistedReferenceIndex) throws {
        let directory = cacheDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(index)
        try data.write(to: cacheFileURL(for: index.documentFingerprint), options: .atomic)
    }

    static func cacheFileURL(for fingerprint: String) -> URL {
        cacheDirectory().appendingPathComponent("\(fingerprint).json")
    }

    private static func cacheDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cauchy/\(indexDirectoryName)", isDirectory: true)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
