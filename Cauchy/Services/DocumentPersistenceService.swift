import Foundation

struct PersistedWorkspace: Codable, Sendable {
    var workspace: DocumentWorkspace
    var bookmarkData: Data?
}

final class DocumentPersistenceService: @unchecked Sendable {
    static let shared = DocumentPersistenceService()

    private let debouncer = Debouncer(delay: 0.5)
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {}

    func applicationSupportRoot() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cauchy/workspaces", isDirectory: true)
    }

    func workspaceDirectory(for workspaceID: UUID) -> URL {
        applicationSupportRoot().appendingPathComponent(workspaceID.uuidString, isDirectory: true)
    }

    func workspaceFileURL(for workspaceID: UUID) -> URL {
        workspaceDirectory(for: workspaceID).appendingPathComponent("workspace.json")
    }

    func thumbnailsDirectory(for workspaceID: UUID) -> URL {
        workspaceDirectory(for: workspaceID).appendingPathComponent("thumbnails", isDirectory: true)
    }

    func thumbnailURL(workspaceID: UUID, filename: String) -> URL {
        thumbnailsDirectory(for: workspaceID).appendingPathComponent(filename)
    }

    func legacySidecarDirectory(for documentURL: URL) -> URL {
        documentURL.appendingPathExtension("cauchy")
    }

    func legacyWorkspaceFileURL(for documentURL: URL) -> URL {
        legacySidecarDirectory(for: documentURL).appendingPathComponent("workspace.json")
    }

    func legacyThumbnailsDirectory(for documentURL: URL) -> URL {
        legacySidecarDirectory(for: documentURL).appendingPathComponent("thumbnails", isDirectory: true)
    }

    func loadWorkspace(for documentURL: URL) throws -> PersistedWorkspace? {
        if let appSupport = try loadFromApplicationSupport(matching: documentURL) {
            return appSupport
        }
        if let legacy = try loadLegacySidecar(for: documentURL) {
            try saveWorkspace(legacy.workspace, bookmarkData: legacy.bookmarkData)
            return legacy
        }
        return nil
    }

    func saveWorkspace(_ workspace: DocumentWorkspace, bookmarkData: Data?) throws {
        let directory = workspaceDirectory(for: workspace.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: thumbnailsDirectory(for: workspace.id),
            withIntermediateDirectories: true
        )

        let persisted = PersistedWorkspace(workspace: workspace, bookmarkData: bookmarkData)
        let data = try encoder.encode(persisted)
        try data.write(to: workspaceFileURL(for: workspace.id), options: .atomic)
    }

    func scheduleSave(
        _ workspace: DocumentWorkspace,
        bookmarkData: Data?,
        onError: (@Sendable (Error) -> Void)? = nil
    ) {
        debouncer.schedule { [weak self] in
            do {
                try self?.saveWorkspace(workspace, bookmarkData: bookmarkData)
            } catch {
                onError?(error)
            }
        }
    }

    func createBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    func resolveBookmark(_ data: Data) throws -> URL {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    func migrateLegacyThumbnails(from documentURL: URL, to workspaceID: UUID) {
        let legacyDir = legacyThumbnailsDirectory(for: documentURL)
        let targetDir = thumbnailsDirectory(for: workspaceID)
        guard FileManager.default.fileExists(atPath: legacyDir.path) else { return }
        try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: legacyDir.path) else { return }
        for file in files {
            let source = legacyDir.appendingPathComponent(file)
            let dest = targetDir.appendingPathComponent(file)
            if !FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.copyItem(at: source, to: dest)
            }
        }
    }

    private func loadFromApplicationSupport(matching documentURL: URL) throws -> PersistedWorkspace? {
        let root = applicationSupportRoot()
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }

        let targetPath = documentURL.standardizedFileURL.path
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ) else { return nil }

        for entry in entries where entry.hasDirectoryPath {
            let fileURL = entry.appendingPathComponent("workspace.json")
            guard FileManager.default.fileExists(atPath: fileURL.path),
                  let data = try? Data(contentsOf: fileURL),
                  let persisted = try? decoder.decode(PersistedWorkspace.self, from: data) else {
                continue
            }
            if persisted.workspace.documentURL.standardizedFileURL.path == targetPath {
                return persisted
            }
        }
        return nil
    }

    private func loadLegacySidecar(for documentURL: URL) throws -> PersistedWorkspace? {
        let fileURL = legacyWorkspaceFileURL(for: documentURL)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let persisted = try decoder.decode(PersistedWorkspace.self, from: data)
        migrateLegacyThumbnails(from: documentURL, to: persisted.workspace.id)
        return persisted
    }
}
