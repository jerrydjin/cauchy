import CryptoKit
import Foundation

struct PersistedReferenceIndex: Codable, Sendable {
    static let schemaVersion = 3

    /// Which model family produced the entries: "on-device", "gemini", or
    /// "legacy-unknown" for caches migrated from v2. Recorded so a future
    /// policy change can decide what is worth rebuilding; nothing is
    /// auto-rebuilt today.
    let builtWith: String
    /// Pages whose extraction failed after retries — re-indexed and merged in
    /// the next time the document is opened.
    let failedPageIndices: [Int]

    let schemaVersion: Int
    let documentFingerprint: String
    let builtAt: Date
    let entries: [PersistedReferenceEntry]

    init(
        documentFingerprint: String,
        builtAt: Date,
        entries: [ReferenceKey: IndexedReference],
        builtWith: String,
        failedPageIndices: [Int]
    ) {
        self.init(
            documentFingerprint: documentFingerprint,
            builtAt: builtAt,
            persistedEntries: entries.map { key, value in
                PersistedReferenceEntry(
                    kind: key.kind.rawValue,
                    number: key.number,
                    formattedBody: value.formattedBody,
                    pageIndex: value.pageIndex
                )
            },
            builtWith: builtWith,
            failedPageIndices: failedPageIndices
        )
    }

    init(
        documentFingerprint: String,
        builtAt: Date,
        persistedEntries: [PersistedReferenceEntry],
        builtWith: String,
        failedPageIndices: [Int]
    ) {
        self.schemaVersion = Self.schemaVersion
        self.documentFingerprint = documentFingerprint
        self.builtAt = builtAt
        self.entries = persistedEntries
        self.builtWith = builtWith
        self.failedPageIndices = failedPageIndices.sorted()
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

    /// Raw SHA-256 of the document bytes. Schema versioning lives in the cache
    /// file name (and the decoded payload), not the fingerprint, so a schema
    /// bump can migrate old caches instead of orphaning them.
    static func fingerprint(for documentURL: URL) throws -> String {
        // Stream the file into the hasher: same digest as hashing Data(contentsOf:)
        // in one shot, without holding a potentially huge PDF in memory.
        let handle = try FileHandle(forReadingFrom: documentURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func load(fingerprint: String) throws -> PersistedReferenceIndex? {
        let url = cacheFileURL(for: fingerprint)
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            let persisted = try decoder.decode(PersistedReferenceIndex.self, from: data)
            guard persisted.schemaVersion == PersistedReferenceIndex.schemaVersion else { return nil }
            guard persisted.documentFingerprint == fingerprint else { return nil }
            touch(url)
            return persisted
        }
        return try migrateLegacyV2(fingerprint: fingerprint)
    }

    /// Marks a cache file as recently used so pruning keeps the documents the
    /// user actually reads. Fingerprints are content hashes, so a re-downloaded
    /// or edited PDF orphans its old cache file forever — pruning is the only
    /// thing that ever deletes them.
    private static func touch(_ url: URL) {
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: url.path
        )
    }

    /// Deletes cache files (all schema versions) that are both outside the 50
    /// most recently used and untouched for over 180 days. Called once per
    /// launch, off the main actor.
    static func pruneStaleCaches(
        keepingNewest keepCount: Int = 50,
        olderThan maxAge: TimeInterval = 180 * 24 * 3600
    ) {
        let directory = cacheDirectory()
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        let dated = entries
            .filter { $0.pathExtension == "json" }
            .map { url -> (url: URL, modified: Date) in
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return (url, modified)
            }
            .sorted { $0.modified > $1.modified }

        let cutoff = Date().addingTimeInterval(-maxAge)
        for (url, modified) in dated.dropFirst(keepCount) where modified < cutoff {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// v2 caches (Gemini-built, before provenance/failed-page tracking) stay
    /// valid: decode with the legacy shape and re-save as v3.
    private static func migrateLegacyV2(fingerprint: String) throws -> PersistedReferenceIndex? {
        struct LegacyV2: Codable {
            let schemaVersion: Int
            let documentFingerprint: String
            let builtAt: Date
            let entries: [PersistedReferenceEntry]
        }

        let legacyURL = cacheDirectory().appendingPathComponent("\(fingerprint)-v2.json")
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return nil }
        let data = try Data(contentsOf: legacyURL)
        let legacy = try decoder.decode(LegacyV2.self, from: data)
        guard legacy.schemaVersion == 2,
              legacy.documentFingerprint == "\(fingerprint)-v2" else { return nil }

        let migrated = PersistedReferenceIndex(
            documentFingerprint: fingerprint,
            builtAt: legacy.builtAt,
            persistedEntries: legacy.entries,
            builtWith: "legacy-unknown",
            failedPageIndices: []
        )
        try? save(migrated)
        return migrated
    }

    static func save(_ index: PersistedReferenceIndex) throws {
        let directory = cacheDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(index)
        try data.write(to: cacheFileURL(for: index.documentFingerprint), options: .atomic)
    }

    static func cacheFileURL(for fingerprint: String) -> URL {
        cacheDirectory().appendingPathComponent("\(fingerprint)-v\(PersistedReferenceIndex.schemaVersion).json")
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
