import Foundation
import Observation

/// Owns one setup operation across Settings redraws. Credentials stay with the vendor CLI.
@MainActor @Observable
final class ConnectorSetupService {
    static let shared = ConnectorSetupService()
    enum Phase: Equatable {
        case idle, installing, signIn, checking, ready, failed(String)
    }
    var phase: Phase = .idle
    var connectorID: AssistantConnectorID?
    var authenticated: Set<AssistantConnectorID> = []
    var loginArguments: [String] = []
    private var operation: Task<Void, Never>?

    var busy: Bool { phase == .installing || phase == .checking }

    func begin(_ id: AssistantConnectorID) {
        guard operation == nil else { return }
        connectorID = id
        phase = .idle
        operation = Task {
            do {
                if id.connector.resolvedBinaryURL == nil {
                    phase = .installing
                    try await install(id)
                }
                try Task.checkCancellation()
                guard let binary = id.connector.resolvedBinaryURL else {
                    throw SetupError.message("Installation finished, but the app could not find the tool. Try again.")
                }
                // Older Claude installations don't implement the dedicated auth command.
                if id == .claudeCode {
                    let help = try await run(binary, ["--help"], timeout: 20)
                    loginArguments = help.range(of: #"(?m)^\s+auth\s"#, options: .regularExpression) != nil ? ["auth", "login"] : []
                } else {
                    loginArguments = id == .codex ? ["login"] : []
                }
                // `codex login status` can exit 0 without a ChatGPT login. Ready
                // means a tiny request to the selected model actually answered.
                phase = .checking
                let modelID = AssistantPreferences.modelChoice(for: id).modelID
                let failure = await ProviderReadinessStore.shared.probe(
                    connectorID: id,
                    modelID: modelID,
                    force: true
                )
                try Task.checkCancellation()
                switch failure {
                case nil:
                    authenticated.insert(id)
                    phase = .ready
                case .notSignedIn, .notInstalled, .cancelled:
                    authenticated.remove(id)
                    phase = .signIn
                default:
                    authenticated.remove(id)
                    phase = .failed(failure?.errorDescription ?? "Could not connect.")
                }
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .failed(error.localizedDescription)
            }
            operation = nil
        }
    }

    func cancel() {
        operation?.cancel()
        // Keep the operation owned until cancellation has drained the process.
    }

    func check() {
        guard operation == nil, let id = connectorID,
              id.connector.resolvedBinaryURL != nil else { return }
        phase = .checking
        operation = Task {
            let modelID = AssistantPreferences.modelChoice(for: id).modelID
            let failure = await ProviderReadinessStore.shared.probe(
                connectorID: id,
                modelID: modelID,
                force: true
            )
            if Task.isCancelled {
                phase = .signIn
            } else if failure == nil {
                authenticated.insert(id)
                phase = .ready
            } else if case .notSignedIn = failure {
                authenticated.remove(id)
                phase = .signIn
            } else {
                authenticated.remove(id)
                phase = .failed(failure?.errorDescription ?? "Could not connect.")
            }
            operation = nil
        }
    }

    static func claudeIsSignedIn(_ output: String) -> Bool {
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return json["loggedIn"] as? Bool == true
    }

    private func install(_ id: AssistantConnectorID) async throws {
        guard let spec = Self.installer(for: id) else { throw SetupError.message("No installer is available.") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cauchy-install-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("install.sh")
        // Download fully before execution; HTTP errors never become shell input.
        _ = try await run(URL(fileURLWithPath: "/usr/bin/curl"),
                          ["--fail", "--location", "--proto", "=https", "--proto-redir", "=https",
                           "--max-time", "120", "--output", script.path, spec.url], timeout: 130)
        _ = try await run(URL(fileURLWithPath: spec.shell), [script.path] + spec.arguments, timeout: 600)
        CLIAgentRunner.invalidateBinaryCache()
    }

    struct Installer {
        let url: String
        let shell: String
        let arguments: [String]
    }
    static func installer(for id: AssistantConnectorID) -> Installer? {
        switch id {
        case .codex: Installer(url: "https://chatgpt.com/codex/install.sh", shell: "/bin/sh", arguments: [])
        case .claudeCode: Installer(url: "https://claude.ai/install.sh", shell: "/bin/bash", arguments: [])
        case .antigravity: Installer(url: "https://antigravity.google/cli/install.sh", shell: "/bin/bash", arguments: [])
        default: nil
        }
    }

    func run(_ binary: URL, _ arguments: [String], timeout: Double) async throws -> String {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cauchy-setup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                var output = ""
                for try await line in CLIAgentRunner.streamLines(binary: binary, arguments: arguments, workingDirectory: directory) {
                    try Task.checkCancellation()
                    output = String((output + line + "\n").suffix(16_000))
                }
                try Task.checkCancellation()
                return output
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw SetupError.message("This step took too long. Check your internet connection and try again.")
            }
            defer { group.cancelAll() }
            return try await group.next() ?? ""
        }
    }
    enum SetupError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let value) = self { value } else { nil } }
    }
}
