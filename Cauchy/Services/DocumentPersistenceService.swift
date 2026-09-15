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

    private struct PendingSnapshot: Sendable {
        let revision: UUID
        let workspace: DocumentWorkspace
        let bookmarkData: Data?
        let onError: (@Sendable (Error) -> Void)?
    }
    // Enqueue synchronously so a shutdown flush also sees saves whose actor
    // scheduling tasks have not run yet. Each document owns its pending value.
    private let snapshots = OSAllocatedUnfairLock(initialState: [UUID: PendingSnapshot]())
    private var pendingSaves: [UUID: Task<Void, Never>] = [:]
    private let rootOverride: URL?

    init(root: URL? = nil) { rootOverride = root }

    // MARK: - Paths (pure, callable synchronously from anywhere)

    nonisolated func applicationSupportRoot() -> URL {
        rootOverride ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
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
        // A close followed immediately by reopen must not load an older file.
        try flushAll()
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

    /// Imports a portable handoff as a new local workspace. A fresh identity
    /// avoids silently replacing this Mac's existing notes if the same package
    /// is opened more than once, while the managed PDF copy means the session
    /// keeps working after an AirDrop/download staging file is removed.
    func importReadingSession(from packageURL: URL) throws -> PersistedWorkspace {
        let (package, packagedPDF) = try ReadingSessionPackageService.read(from: packageURL)
        var workspace = package.workspace
        workspace.id = UUID()
        workspace.lastOpenedAt = Date()

        let directory = workspaceDirectory(for: workspace.id)
        let documentURL = directory.appendingPathComponent(package.documentFilename)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: packagedPDF, to: documentURL)
            workspace.documentURL = documentURL
            try saveWorkspace(workspace, bookmarkData: nil)
            return PersistedWorkspace(workspace: workspace, bookmarkData: nil)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    /// Debounced save; safe to call at any frequency from the main actor. The
    /// encode and disk write happen on this actor, off the main thread.
    nonisolated func scheduleSave(
        _ workspace: DocumentWorkspace,
        bookmarkData: Data?,
        onError: (@Sendable (Error) -> Void)? = nil
    ) {
        let snapshot = PendingSnapshot(revision: UUID(), workspace: workspace,
                                       bookmarkData: bookmarkData, onError: onError)
        snapshots.withLock { $0[workspace.id] = snapshot }
        Task { await debounceSave(id: workspace.id, revision: snapshot.revision) }
    }

    private func debounceSave(id: UUID, revision: UUID) {
        guard snapshots.withLock({ $0[id]?.revision }) == revision else { return }
        pendingSaves[id]?.cancel()
        pendingSaves[id] = Task {
            do { try await Task.sleep(for: .seconds(0.5)) } catch { return }
            guard !Task.isCancelled else { return }
            try? flush(id: id)
        }
    }

    func flush(id: UUID) throws {
        pendingSaves.removeValue(forKey: id)?.cancel()
        guard let snapshot = snapshots.withLock({ $0[id] }) else { return }
        do {
            try saveWorkspace(snapshot.workspace, bookmarkData: snapshot.bookmarkData)
            snapshots.withLock {
                if $0[id]?.revision == snapshot.revision { $0[id] = nil }
            }
        } catch {
            snapshot.onError?(error)
            throw error
        }
    }

    func flushAll() throws {
        var firstError: Error?
        for id in snapshots.withLock({ Array($0.keys) }) {
            do { try flush(id: id) } catch { firstError = firstError ?? error }
        }
        if let firstError { throw firstError }
    }

    /// Loads one workspace in full (highlights and every thread) by its id.
    /// The summaries the dashboard lists deliberately omit all of that, so
    /// library-wide search has to come back for it.
    func loadWorkspace(id: UUID) -> PersistedWorkspace? {
        if let pending = snapshots.withLock({ $0[id] }) {
            return PersistedWorkspace(workspace: pending.workspace, bookmarkData: pending.bookmarkData)
        }
        return persistedWorkspace(inDirectory: workspaceDirectory(for: id))
    }

    /// Permanently removes a workspace directory (workspace.json, summary,
    /// thumbnails). Hiding a recent document deliberately does not call this.
    func deleteWorkspace(id: UUID) throws {
        pendingSaves.removeValue(forKey: id)?.cancel()
        snapshots.withLock { $0[id] = nil }
        let directory = workspaceDirectory(for: id)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    // MARK: - Summaries

    func listWorkspaceSummaries() -> [WorkspaceSummary] {
        let root = applicationSupportRoot()
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil
        )) ?? []

        var summaries: [WorkspaceSummary] = []
        for entry in entries where entry.hasDirectoryPath {
            if let summary = summary(inDirectory: entry) {
                summaries.append(summary)
            }
        }
        var byID = Dictionary(summaries.map { ($0.workspaceID, $0) }, uniquingKeysWith: { _, last in last })
        for pending in snapshots.withLock({ Array($0.values) }) {
            byID[pending.workspace.id] = Self.makeSummary(for: PersistedWorkspace(
                workspace: pending.workspace, bookmarkData: pending.bookmarkData))
        }
        return byID.values.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
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
