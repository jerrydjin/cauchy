import Foundation
import Synchronization
import Darwin

enum CLIAgentError: LocalizedError {
    case launchFailed(String)
    case timedOut
    case processFailed(exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "The assistant did not finish this request in time. Try again; completed work is saved."
        case .launchFailed(let message):
            return "Could not launch the CLI: \(message)"
        case .processFailed(let exitCode, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "The CLI exited with code \(exitCode)." : detail
        }
    }
}

/// Finds and runs the user's locally installed agent CLIs (claude / codex / agy).
/// The API calls are made by the vendor's own binary under the user's own
/// sign-in; the app never sees or handles a credential.
enum CLIAgentRunner {
    // MARK: - Binary discovery

    @MainActor private static var locateCache: [String: URL] = [:]

    /// GUI apps launch with a minimal PATH, so search the standard install
    /// locations explicitly in addition to whatever PATH we inherited.
    @MainActor
    static func locateBinary(named name: String) -> URL? {
        if let cached = locateCache[name], FileManager.default.isExecutableFile(atPath: cached.path) {
            return cached
        }

        let home = NSHomeDirectory()
        var candidates = [
            "\(home)/.local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "\(home)/bin/\(name)",
            "\(home)/.claude/local/\(name)",
            "\(home)/.codex/bin/\(name)",
            "/usr/bin/\(name)",
        ]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/\(name)" }
        }

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            let url = URL(fileURLWithPath: candidate)
            locateCache[name] = url
            return url
        }
        return nil
    }

    /// Drops cached lookups so a CLI installed while the app is running is
    /// picked up after the user revisits Settings.
    @MainActor
    static func invalidateBinaryCache() {
        locateCache.removeAll()
    }

    /// Shared by reading requests and the embedded provider sign-in.
    nonisolated static var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        // Make sure the CLI can find its own helpers (node, etc.).
        let extraPaths = [
            "\(NSHomeDirectory())/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
        environment["PATH"] = (extraPaths + [environment["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
        // The whole point of this provider is the user's own CLI sign-in.
        // Strip API-key/base-URL overrides so a stray environment variable
        // can never silently reroute or re-bill the request.
        for key in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL", "OPENAI_API_KEY", "GEMINI_API_KEY", "GOOGLE_API_KEY"] {
            environment.removeValue(forKey: key)
        }
        return environment
    }

    // MARK: - Process execution

    /// Process and FileHandle are thread-safe Objective-C classes; this wrapper
    /// only exists to move them across the stream/termination closures.
    private final class ChildProcess: @unchecked Sendable {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let queue = DispatchQueue(label: "cauchy.cli.output")
        let output = Mutex(Data())
        let diagnostics = Mutex(Data())
        let finished = Mutex(false)

        func terminateIfRunning() {
            guard process.isRunning else { return }
            process.terminate()
            queue.asyncAfter(deadline: .now() + 2) { [process] in
                if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
            }
        }

        func makeNonblocking(_ handle: FileHandle) {
            let fd = handle.fileDescriptor
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        }

        // Never wait for EOF: a vendor helper can inherit the pipe and keep
        // it open after the request process exits. Drain bytes already written.
        func readAvailable(_ handle: FileHandle, receive: (Data) -> Void) -> Bool {
            var bytes = [UInt8](repeating: 0, count: 16_384)
            while true {
                let count = bytes.withUnsafeMutableBytes { Darwin.read(handle.fileDescriptor, $0.baseAddress, $0.count) }
                if count > 0 { receive(Data(bytes.prefix(count))) }
                else if count < 0 && errno == EINTR { continue }
                else { return count == 0 }
            }
        }

        func drain(_ continuation: AsyncThrowingStream<String, Error>.Continuation, flush: Bool = false) {
            guard !finished.withLock({ $0 }) else { return }
            let outputClosed = readAvailable(stdout.fileHandleForReading) { data in output.withLock { $0.append(data) } }
            let diagnosticsClosed = readAvailable(stderr.fileHandleForReading) { data in
                diagnostics.withLock { buffer in
                    buffer.append(data)
                    if buffer.count > 4_000 { buffer = Data(buffer.suffix(4_000)) }
                }
            }
            if outputClosed { stdout.fileHandleForReading.readabilityHandler = nil }
            if diagnosticsClosed { stderr.fileHandleForReading.readabilityHandler = nil }
            let lines = output.withLock { buffer -> [String] in
                var lines: [String] = []
                while let newline = buffer.firstIndex(of: 10) {
                    lines.append(String(decoding: buffer[..<newline], as: UTF8.self))
                    buffer.removeSubrange(...newline)
                }
                if flush && !buffer.isEmpty {
                    lines.append(String(decoding: buffer, as: UTF8.self))
                    buffer.removeAll()
                }
                return lines
            }
            for line in lines { continuation.yield(line) }
        }

        func finish(_ continuation: AsyncThrowingStream<String, Error>.Continuation, error: Error? = nil) {
            guard !finished.withLock({ $0 }) else { return }
            drain(continuation, flush: true)
            finished.withLock { $0 = true }
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            process.terminationHandler = nil
            try? stdout.fileHandleForReading.close()
            try? stderr.fileHandleForReading.close()
            if let error { continuation.finish(throwing: error) }
            else if process.terminationStatus != 0 {
                let message = diagnostics.withLock { String(decoding: $0, as: UTF8.self) }
                continuation.finish(throwing: CLIAgentError.processFailed(exitCode: process.terminationStatus, stderr: message))
            } else { continuation.finish() }
        }
    }

    /// Completion follows the request process, not an inherited output pipe.
    /// Indexing may specify a deadline; ordinary chat keeps its existing policy.
    nonisolated static func streamLines(
        binary: URL,
        arguments: [String],
        workingDirectory: URL,
        timeout: TimeInterval? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let child = ChildProcess()
            let process = child.process
            process.executableURL = binary
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory
            process.standardOutput = child.stdout
            process.standardError = child.stderr
            process.standardInput = FileHandle.nullDevice
            process.environment = Self.environment

            child.makeNonblocking(child.stdout.fileHandleForReading)
            child.makeNonblocking(child.stderr.fileHandleForReading)
            child.stdout.fileHandleForReading.readabilityHandler = { _ in
                child.queue.async { child.drain(continuation) }
            }
            child.stderr.fileHandleForReading.readabilityHandler = { _ in
                child.queue.async { child.drain(continuation) }
            }
            process.terminationHandler = { _ in
                child.queue.async { child.finish(continuation) }
            }
            continuation.onTermination = { termination in
                if case .cancelled = termination { child.terminateIfRunning() }
            }
            do {
                try process.run()
                // The child has its own duplicated descriptors.
                try? child.stdout.fileHandleForWriting.close()
                try? child.stderr.fileHandleForWriting.close()
            } catch {
                child.stdout.fileHandleForReading.readabilityHandler = nil
                child.stderr.fileHandleForReading.readabilityHandler = nil
                process.terminationHandler = nil
                continuation.finish(throwing: CLIAgentError.launchFailed(error.localizedDescription))
                return
            }
            if let timeout {
                child.queue.asyncAfter(deadline: .now() + max(0, timeout)) { [weak child] in
                    guard let child else { return }
                    guard !child.finished.withLock({ $0 }) else { return }
                    child.terminateIfRunning()
                    child.finish(continuation, error: CLIAgentError.timedOut)
                }
            }
        }
    }
}
