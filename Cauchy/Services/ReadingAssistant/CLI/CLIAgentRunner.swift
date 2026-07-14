import Foundation
import Synchronization

enum CLIAgentError: LocalizedError {
    case launchFailed(String)
    case processFailed(exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return "Could not launch the CLI: \(message)"
        case .processFailed(let exitCode, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "The CLI exited with code \(exitCode)." : detail
        }
    }
}

/// Finds and runs the user's locally installed agent CLIs (claude / codex).
/// The API calls are made by the vendor's own binary under the user's own
/// sign-in; the app never sees or handles a credential.
enum CLIAgentRunner {
    // MARK: - Binary discovery

    @MainActor private static var locateCache: [String: URL] = [:]

    /// GUI apps launch with a minimal PATH, so search the standard install
    /// locations explicitly in addition to whatever PATH we inherited.
    @MainActor
    static func locateBinary(named name: String) -> URL? {
        if let cached = locateCache[name] {
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

    // MARK: - Process execution

    /// Process and FileHandle are thread-safe Objective-C classes; this wrapper
    /// only exists to move them across the stream/termination closures.
    private final class ChildProcess: @unchecked Sendable {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        func terminateIfRunning() {
            if process.isRunning {
                process.terminate()
            }
        }
    }

    /// Launches the binary and yields stdout line by line. Throws
    /// CLIAgentError.processFailed (with captured stderr) on non-zero exit.
    /// Cancelling the consuming task terminates the child process.
    nonisolated static func streamLines(
        binary: URL,
        arguments: [String],
        workingDirectory: URL
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
            for key in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL", "OPENAI_API_KEY"] {
                environment.removeValue(forKey: key)
            }
            process.environment = environment

            // Drain stderr as it arrives so a chatty child can't deadlock.
            let stderrBuffer = Mutex(Data())
            child.stderr.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    stderrBuffer.withLock { $0.append(data) }
                }
            }

            do {
                try process.run()
            } catch {
                child.stderr.fileHandleForReading.readabilityHandler = nil
                continuation.finish(throwing: CLIAgentError.launchFailed(error.localizedDescription))
                return
            }

            continuation.onTermination = { termination in
                if case .cancelled = termination {
                    child.terminateIfRunning()
                }
            }

            Task.detached {
                do {
                    for try await line in child.stdout.fileHandleForReading.bytes.lines {
                        continuation.yield(line)
                    }
                } catch {
                    // Fall through to exit-status handling.
                }
                child.process.waitUntilExit()
                child.stderr.fileHandleForReading.readabilityHandler = nil

                let status = child.process.terminationStatus
                if status == 0 {
                    continuation.finish()
                } else {
                    let data = stderrBuffer.withLock { $0 }
                    let stderrText = String(data: data.suffix(4000), encoding: .utf8) ?? ""
                    continuation.finish(throwing: CLIAgentError.processFailed(exitCode: status, stderr: stderrText))
                }
            }
        }
    }
}
