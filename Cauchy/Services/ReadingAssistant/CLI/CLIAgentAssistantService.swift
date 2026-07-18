import Foundation

/// Reading assistant backed by a locally installed agent CLI (Claude Code or
/// Codex). The user signs in once in their terminal with their own plan; the
/// app spawns the CLI per question and streams its output. No API key is ever
/// stored or seen by the app.
@MainActor
final class CLIAgentAssistantService: ReadingAssistantProtocol {
    let provider: ReadingAssistantProvider

    private var context: ReadingContext?
    private var history: [ThreadMessage] = []
    private(set) var isResponding = false

    init(provider: ReadingAssistantProvider) {
        precondition(provider == .claudeCode || provider == .codex)
        self.provider = provider
    }

    static func binaryName(for provider: ReadingAssistantProvider) -> String {
        provider == .codex ? "codex" : "claude"
    }

    static func binaryURL(for provider: ReadingAssistantProvider) -> URL? {
        CLIAgentRunner.locateBinary(named: binaryName(for: provider))
    }

    static func availability(for provider: ReadingAssistantProvider) -> ReadingAssistantAvailability {
        binaryURL(for: provider) != nil ? .available(provider) : .cliNotInstalled(provider)
    }

    var availability: ReadingAssistantAvailability {
        Self.availability(for: provider)
    }

    func resetSession(context: ReadingContext) {
        self.context = context
        history = []
    }

    func restoreSession(context: ReadingContext, messages: [ThreadMessage]) {
        self.context = context
        history = messages
    }

    func ask(
        question: String,
        onPartial: ((String) -> Void)? = nil
    ) async throws -> String {
        guard !isResponding else {
            throw ReadingAssistantError.sessionBusy
        }
        guard let binary = Self.binaryURL(for: provider) else {
            throw ReadingAssistantError.notAvailable(availability)
        }

        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        isResponding = true
        defer { isResponding = false }

        let arguments = makeArguments(question: trimmed)
        var parser: any CLIAgentStreamParsing = provider == .codex
            ? CodexStreamParser()
            : ClaudeCodeStreamParser()

        do {
            let lines = CLIAgentRunner.streamLines(
                binary: binary,
                arguments: arguments,
                workingDirectory: FileManager.default.temporaryDirectory
            )
            for try await line in lines {
                if let partial = parser.consume(line: line) {
                    onPartial?(AssistantResponseNormalizer.normalize(partial))
                }
            }
        } catch let error as CLIAgentError {
            throw ReadingAssistantError.api(friendlyMessage(parser.errorMessage ?? error.localizedDescription))
        }

        if let message = parser.errorMessage {
            throw ReadingAssistantError.api(friendlyMessage(message))
        }
        guard let finalText = parser.finalText,
              !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReadingAssistantError.api("\(provider.cliDisplayName) produced no response.")
        }

        let normalized = AssistantResponseNormalizer.normalize(finalText)
        onPartial?(normalized)

        history.append(ThreadMessage(role: .user, content: trimmed))
        history.append(ThreadMessage(role: .assistant, content: normalized))
        return normalized
    }

    // MARK: - Prompt & argument construction

    private func makeArguments(question: String) -> [String] {
        let instructions = instructionsText()
        let transcript = Self.transcriptPrompt(history: history, question: question)

        switch provider {
        case .codex:
            // Codex has no separate system-prompt flag; prepend instructions.
            // The sandbox flag keeps the agent read-only on the user's machine.
            // Model and effort are always passed explicitly because
            // ~/.codex/config.toml is shared with the ChatGPT desktop app,
            // which rewrites it — the user's in-app choice must win.
            return [
                "exec", instructions + "\n\n" + transcript,
                "--json",
                "--skip-git-repo-check",
                "--sandbox", "read-only",
                "--model", ModelProviderPreferences.selectedModelID(for: .codex),
                "-c", "model_reasoning_effort=\"medium\"",
            ]
        default:
            // Tools are disabled: this is a chat provider, so the agent must
            // never run commands or edit files on the user's machine. The model
            // is passed explicitly so answers don't silently depend on the
            // user's CLI-side default.
            return [
                "-p", transcript,
                "--output-format", "stream-json",
                "--include-partial-messages",
                "--verbose",
                "--tools", "",
                "--no-session-persistence",
                "--model", ModelProviderPreferences.selectedModelID(for: .claudeCode),
                "--append-system-prompt", instructions,
            ]
        }
    }

    private func instructionsText() -> String {
        if let context {
            return ReadingPromptBuilder.instructions(for: context, provider: provider)
        }
        return "You are a precise math reading assistant. Answer concisely. Write all mathematics as LaTeX inside $...$ or $$...$$ delimiters; never emit LaTeX commands outside math delimiters."
    }

    /// The CLI runs one-shot per question, so earlier turns are replayed as a
    /// transcript inside the prompt (simple and version-independent, at the
    /// cost of resending history — which the user's plan quota absorbs).
    static func transcriptPrompt(history: [ThreadMessage], question: String) -> String {
        guard !history.isEmpty else { return question }
        var lines = ["Earlier conversation about this passage:", ""]
        for message in history {
            lines.append("\(message.role == .user ? "User" : "Assistant"): \(message.content)")
        }
        lines.append("")
        lines.append("New question from the user — answer this:")
        lines.append(question)
        return lines.joined(separator: "\n")
    }

    private func friendlyMessage(_ raw: String) -> String {
        let lowered = raw.lowercased()
        if lowered.contains("login") || lowered.contains("authentication") || lowered.contains("unauthorized") || lowered.contains("401") {
            switch provider {
            case .codex:
                return "Codex is not signed in. Run `codex login` in Terminal, then try again."
            default:
                return "Claude Code is not signed in. Run `claude` in Terminal and log in, then try again."
            }
        }
        return raw
    }
}
