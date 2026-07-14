import Foundation
import os

struct PersistedWorkspace: Codable, Sendable {
    var workspace: DocumentWorkspace
    var bookmarkData: Data?
}

/// Lightweight per-workspace sidecar so lookups and the dashboard don't have
/// to decode every full workspace (including entire chat threads).
struct WorkspaceSummary: Codable, Sendable {
    var workspaceID: UUID
    var documentURL: URL
    var lastOpenedAt: Date
    var highlightCount: Int
    var bookmarkData: Data?
}

actor DocumentPersistenceService {
    static let shared = DocumentPersistenceService()

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

    // Saves are debounced on the actor, but scheduleSave itself is called
    // synchronously from the main actor; the ticket makes ordering explicit so
    // a slow-to-arrive older snapshot can never overwrite a newer one.
    private let scheduleTicket = OSAllocatedUnfairLock(initialState: 0)
    private var latestTicket = 0
    private var pendingSave: Task<Void, Never>?

    private init() {}

    // MARK: - Paths (pure, callable synchronously from anywhere)

    nonisolated func applicationSupportRoot() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cauchy/workspaces", isDirectory: true)
    }

    nonisolated func workspaceDirectory(for workspaceID: UUID) -> URL {
        applicationSupportRoot().appendingPathComponent(workspaceID.uuidString, isDirectory: true)
    }

    nonisolated func workspaceFileURL(for workspaceID: UUID) -> URL {
        workspaceDirectory(for: workspaceID).appendingPathComponent("workspace.json")
    }

    nonisolated func summaryFileURL(for workspaceID: UUID) -> URL {
        workspaceDirectory(for: workspaceID).appendingPathComponent("summary.json")
    }

    nonisolated func thumbnailsDirectory(for workspaceID: UUID) -> URL {
        workspaceDirectory(for: workspaceID).appendingPathComponent("thumbnails", isDirectory: true)
    }

    nonisolated func thumbnailURL(workspaceID: UUID, filename: String) -> URL {
        thumbnailsDirectory(for: workspaceID).appendingPathComponent(filename)
    }

    nonisolated func legacySidecarDirectory(for documentURL: URL) -> URL {
        documentURL.appendingPathExtension("cauchy")
    }

    nonisolated func legacyWorkspaceFileURL(for documentURL: URL) -> URL {
        legacySidecarDirectory(for: documentURL).appendingPathComponent("workspace.json")
    }

    nonisolated func legacyThumbnailsDirectory(for documentURL: URL) -> URL {
        legacySidecarDirectory(for: documentURL).appendingPathComponent("thumbnails", isDirectory: true)
    }

    // MARK: - Bookmarks (no actor state)

    // Security-scoped bookmarks only exist inside the App Sandbox. The app now
    // ships unsandboxed (it spawns the user's claude/codex CLIs), so fall back
    // to plain bookmarks there — and keep resolving old security-scoped ones.
    nonisolated func createBookmark(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            return try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
    }

    nonisolated func resolveBookmark(_ data: Data) throws -> URL {
        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            _ = url.startAccessingSecurityScopedResource()
            return url
        }
        return try URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    // MARK: - Load / save

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

        try writeSummary(for: persisted)
    }

    /// Debounced save; safe to call at any frequency from the main actor. The
    /// encode and disk write happen on this actor, off the main thread.
    nonisolated func scheduleSave(
        _ workspace: DocumentWorkspace,
        bookmarkData: Data?,
        onError: (@Sendable (Error) -> Void)? = nil
    ) {
        let ticket = scheduleTicket.withLock { state in
            state += 1
            return state
        }
        Task {
            await self.debounceSave(ticket: ticket, workspace: workspace, bookmarkData: bookmarkData, onError: onError)
        }
    }

    private func debounceSave(
        ticket: Int,
        workspace: DocumentWorkspace,
        bookmarkData: Data?,
        onError: (@Sendable (Error) -> Void)?
    ) {
        guard ticket > latestTicket else { return }
        latestTicket = ticket

        pendingSave?.cancel()
        pendingSave = Task {
            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled else { return }
            do {
                try saveWorkspace(workspace, bookmarkData: bookmarkData)
            } catch {
                onError?(error)
            }
        }
    }

    // MARK: - Summaries

    func listWorkspaceSummaries() -> [WorkspaceSummary] {
        let root = applicationSupportRoot()
        guard FileManager.default.fileExists(atPath: root.path),
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: root,
                  includingPropertiesForKeys: nil
              )
        else { return [] }

        var summaries: [WorkspaceSummary] = []
        for entry in entries where entry.hasDirectoryPath {
            if let summary = summary(inDirectory: entry) {
                summaries.append(summary)
            }
        }
        return summaries.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    /// Reads a directory's summary, falling back to a full workspace decode
    /// (and writing the summary for next time) for pre-summary directories.
    private func summary(inDirectory directory: URL) -> WorkspaceSummary? {
        let summaryURL = directory.appendingPathComponent("summary.json")
        if let data = try? Data(contentsOf: summaryURL),
           let summary = try? decoder.decode(WorkspaceSummary.self, from: data) {
            return summary
        }

        guard let persisted = persistedWorkspace(inDirectory: directory) else { return nil }
        try? writeSummary(for: persisted)
        return Self.makeSummary(for: persisted)
    }

    private func persistedWorkspace(inDirectory directory: URL) -> PersistedWorkspace? {
        let fileURL = directory.appendingPathComponent("workspace.json")
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let persisted = try? decoder.decode(PersistedWorkspace.self, from: data)
        else { return nil }
        return persisted
    }

    private func writeSummary(for persisted: PersistedWorkspace) throws {
        let data = try encoder.encode(Self.makeSummary(for: persisted))
        try data.write(to: summaryFileURL(for: persisted.workspace.id), options: .atomic)
    }

    private static func makeSummary(for persisted: PersistedWorkspace) -> WorkspaceSummary {
        WorkspaceSummary(
            workspaceID: persisted.workspace.id,
            documentURL: persisted.workspace.documentURL,
            lastOpenedAt: persisted.workspace.lastOpenedAt,
            highlightCount: persisted.workspace.highlights.count,
            bookmarkData: persisted.bookmarkData
        )
    }

    // MARK: - Lookup

    private func loadFromApplicationSupport(matching documentURL: URL) throws -> PersistedWorkspace? {
        let root = applicationSupportRoot()
        guard FileManager.default.fileExists(atPath: root.path),
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: root,
                  includingPropertiesForKeys: nil
              )
        else { return nil }

        let targetPath = documentURL.standardizedFileURL.path

        for entry in entries where entry.hasDirectoryPath {
            guard let summary = summary(inDirectory: entry) else { continue }
            if summary.documentURL.standardizedFileURL.path == targetPath {
                return persistedWorkspace(inDirectory: entry)
            }
        }
        return nil
    }

    // MARK: - Legacy migration

    private func loadLegacySidecar(for documentURL: URL) throws -> PersistedWorkspace? {
        let fileURL = legacyWorkspaceFileURL(for: documentURL)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let persisted = try decoder.decode(PersistedWorkspace.self, from: data)
        migrateLegacyThumbnails(from: documentURL, to: persisted.workspace.id)
        return persisted
    }

    private func migrateLegacyThumbnails(from documentURL: URL, to workspaceID: UUID) {
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
}
