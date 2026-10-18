import Foundation
import FoundationModels

/// Reading assistant backed by a locally installed agent CLI (Claude Code,
/// Codex, or Antigravity). The user signs in once in their terminal with their own plan; the
/// app spawns the CLI per question and streams its output. No API key is ever
/// stored or seen by the app.
@MainActor
final class CLIAgentAssistantService: ReadingAssistantProtocol {
    let provider: AssistantConnectorID

    /// The model to request, or nil to let the CLI use whatever it is
    /// configured with. Captured at init so an answer always uses the choice
    /// that was live when the assistant was built.
    private let modelID: String?
    private let connector: AssistantConnector
    private let binary: String

    private var context: ReadingContext?
    private var history: [ThreadMessage] = []
    private(set) var isResponding = false
    /// Set by tests so a fake binary is launched without searching the machine.
    private let explicitBinaryURL: URL?

    init(connector id: AssistantConnectorID, modelID: String?, binaryURL: URL? = nil) {
        let connector = id.connector
        self.provider = id
        self.connector = connector
        self.binary = connector.binaryName ?? ""
        self.modelID = modelID
        self.explicitBinaryURL = binaryURL
    }

    var availability: ReadingAssistantAvailability {
        connector.availability
    }

    func resetSession(context: ReadingContext) {
        self.context = context
        history = []
    }

    func restoreSession(context: ReadingContext, messages: [ThreadMessage]) {
        self.context = context
        history = messages
    }

    /// Tests shorten this so a sleeping fake CLI fails as a timeout instead of
    /// waiting out a real answer.
    var requestTimeout = CLIInvocation.chatTimeout

    func ask(
        question: String,
        retrieval: AskRetrieval,
        onPartial: ((String) -> Void)? = nil
    ) async throws -> String {
        guard !isResponding else {
            throw ReadingAssistantError.sessionBusy
        }
        guard let binaryURL = explicitBinaryURL ?? CLIAgentRunner.locateBinary(named: binary) else {
            throw AssistantFailure.notInstalled(provider)
        }

        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        isResponding = true
        defer { isResponding = false }

        let arguments = makeArguments(question: trimmed, retrieval: retrieval)
        let output = await CLIInvocation.execute(
            binary: binaryURL,
            provider: provider,
            arguments: arguments,
            timeout: requestTimeout,
            onPartial: { partial in
                onPartial?(AssistantResponseNormalizer.normalize(partial))
            }
        )
        if output.cancelled || Task.isCancelled {
            throw AssistantFailure.cancelled
        }
        if let failure = AssistantFailure.classify(
            connectorID: provider,
            modelID: modelID,
            parserError: output.parserError,
            parserText: output.text,
            rawOutput: output.raw,
            processError: output.processError
        ) {
            throw failure
        }
        guard let finalText = output.text,
              !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AssistantFailure.emptyOutput(provider)
        }

        let normalized = AssistantResponseNormalizer.normalize(finalText)
        onPartial?(normalized)

        history.append(ThreadMessage(role: .user, content: trimmed))
        history.append(ThreadMessage(role: .assistant, content: normalized))
        return normalized
    }

    // MARK: - Prompt & argument construction

    private func makeArguments(question: String, retrieval: AskRetrieval) -> [String] {
        // Retrieval rides the one-shot prompt only — it is never appended to
        // the stored history, so re-asks don't compound it. Exact statements
        // come before passages: they are source text, though extraction can be lossy.
        var instructions = instructionsText()
        let budgets = ReadingPromptBuilder.evidenceBudgets(for: provider)
        if let block = ReadingPromptBuilder.referencedStatementsBlock(retrieval.statements, characterBudget: budgets.statements) {
            instructions += "\n\n" + block
        }
        if let block = ReadingPromptBuilder.retrievedPassagesBlock(retrieval.passages, characterBudget: budgets.passages) {
            instructions += "\n\n" + block
        }
        if let block = ReadingPromptBuilder.citableSourcesBlock(retrieval.citableSources) {
            instructions += "\n\n" + block
        }
        let transcript = Self.transcriptPrompt(history: history, question: question)

        switch provider {
        case .codex:
            // Codex has no separate system-prompt flag; prepend instructions.
            // The sandbox flag keeps the agent read-only on the user's machine.
            // A chosen model is passed explicitly because ~/.codex/config.toml
            // is shared with the ChatGPT desktop app, which rewrites it — the
            // user's in-app choice must win. Omitting the flag is itself a
            // choice ("Match my CLI") and then that config wins instead.
            return CLIInvocation.codexArguments(prompt: instructions + "\n\n" + transcript, modelID: modelID)
        case .antigravity:
            // agy has neither a system-prompt nor a model flag (the model is
            // whatever the user set with /model in the agy TUI), so
            // instructions ride the prompt. --sandbox keeps the run inside the
            // OS sandbox; headless mode also soft-denies any tool that would
            // need approval, and the working directory is the temp dir.
            return CLIInvocation.antigravityArguments(prompt: instructions + "\n\n" + transcript)
        default:
            // Tools are disabled: this is a chat provider, so the agent must
            // never run commands or edit files on the user's machine. The model
            // is passed explicitly so answers don't silently depend on the
            // user's CLI-side default.
            return CLIInvocation.claudeArguments(prompt: transcript, instructions: instructions, modelID: modelID)
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

}

/// How a one-shot CLI request is spelled, and the one place its stdout is read.
/// Ask, the readiness probe, and reference indexing all go through `execute`,
/// which turns process failures into data instead of letting them escape.
enum CLIInvocation {
    /// A stuck chat becomes an error in the transcript. Long enough that a
    /// reasoning model can finish a proof.
    static let chatTimeout: TimeInterval = 600
    static let probeTimeout: TimeInterval = 90

    struct Output: Sendable {
        var text: String?
        var parserError: String?
        var raw: String
        var processError: CLIAgentError?
        var cancelled: Bool
    }

    static func codexArguments(prompt: String, modelID: String?) -> [String] {
        [
            "exec", prompt,
            "--json",
            "--skip-git-repo-check",
            "--sandbox", "read-only",
            "-c", "model_reasoning_effort=\"medium\"",
        ] + modelArguments(modelID, flag: "--model")
    }

    static func claudeArguments(prompt: String, instructions: String, modelID: String?) -> [String] {
        [
            "-p", prompt,
            "--output-format", "stream-json",
            "--include-partial-messages",
            "--verbose",
            "--tools", "",
            "--no-session-persistence",
            "--append-system-prompt", instructions,
        ] + modelArguments(modelID, flag: "--model")
    }

    static func antigravityArguments(prompt: String) -> [String] {
        ["-p", prompt, "--sandbox"]
    }

    static func modelArguments(_ modelID: String?, flag: String) -> [String] {
        guard let modelID, !modelID.isEmpty else { return [] }
        return [flag, modelID]
    }

    static func makeParser(for provider: AssistantConnectorID) -> any CLIAgentStreamParsing {
        switch provider {
        case .codex: CodexStreamParser()
        case .antigravity: AntigravityStreamParser()
        default: ClaudeCodeStreamParser()
        }
    }

    @MainActor
    static func execute(
        binary: URL,
        provider: AssistantConnectorID,
        arguments: [String],
        timeout: TimeInterval?,
        onPartial: ((String) -> Void)?
    ) async -> Output {
        var parser = makeParser(for: provider)
        var raw = ""
        let lines = CLIAgentRunner.streamLines(
            binary: binary,
            arguments: arguments,
            workingDirectory: FileManager.default.temporaryDirectory,
            timeout: timeout
        )
        do {
            for try await line in lines {
                if raw.utf8.count < 32_000 {
                    raw += line
                    raw += "\n"
                }
                if let partial = parser.consume(line: line) {
                    onPartial?(partial)
                }
            }
        } catch is CancellationError {
            return Output(text: parser.finalText, parserError: parser.errorMessage, raw: raw, processError: nil, cancelled: true)
        } catch let error as CLIAgentError {
            return Output(
                text: parser.finalText,
                parserError: parser.errorMessage,
                raw: raw,
                processError: error,
                cancelled: Task.isCancelled
            )
        } catch {
            if Task.isCancelled { 
                return Output(text: parser.finalText, parserError: parser.errorMessage, raw: raw, processError: nil, cancelled: true)
            }
            return Output(
                text: parser.finalText,
                parserError: parser.errorMessage,
                raw: raw,
                processError: .launchFailed(error.localizedDescription),
                cancelled: false
            )
        }
        return Output(text: parser.finalText, parserError: parser.errorMessage, raw: raw, processError: nil, cancelled: false)
    }
}

/// Adapts the signed-in CLI connectors to the same text-generation interface
/// used by reference indexing. Each request is isolated, read-only, and has no
/// tools; the indexer still checks every result against the PDF text.
struct CLIIndexLanguageModel: LanguageModel {
    typealias Executor = CLIIndexLanguageModelExecutor

    let connectorID: AssistantConnectorID
    let modelID: String?

    var capabilities: LanguageModelCapabilities { LanguageModelCapabilities([]) }

    var executorConfiguration: CLIIndexLanguageModelExecutor.Configuration {
        .init(connectorID: connectorID, modelID: modelID)
    }
}

struct CLIIndexLanguageModelExecutor: LanguageModelExecutor {
    typealias Model = CLIIndexLanguageModel

    struct Configuration: Hashable, Sendable {
        let connectorID: AssistantConnectorID
        let modelID: String?
    }

    let configuration: Configuration

    init(configuration: Configuration) throws {
        self.configuration = configuration
    }

    func prewarm(model: CLIIndexLanguageModel, transcript: Transcript) {}

    func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: CLIIndexLanguageModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        let connector = configuration.connectorID.connector
        guard let binary = connector.binaryName,
              let binaryURL = await CLIAgentRunner.locateBinary(named: binary) else {
            throw ReadingAssistantError.notAvailable(.cliNotInstalled(configuration.connectorID))
        }
        let prompt = CloudPrompt(transcript: request.transcript)
        let question = prompt.sendableTurns.last?.text ?? ""
        let instructions = prompt.instructions ?? ""
        let arguments: [String]
        switch configuration.connectorID {
        case .codex:
            arguments = CLIInvocation.codexArguments(prompt: instructions + "\n\n" + question, modelID: configuration.modelID)
        case .antigravity:
            arguments = CLIInvocation.antigravityArguments(prompt: instructions + "\n\n" + question)
        default:
            arguments = CLIInvocation.claudeArguments(prompt: question, instructions: instructions, modelID: configuration.modelID)
        }

        let output = await CLIInvocation.execute(
            binary: binaryURL,
            provider: configuration.connectorID,
            arguments: arguments,
            timeout: 180,
            onPartial: nil
        )
        if output.cancelled { throw CancellationError() }
        if let failure = AssistantFailure.classify(
            connectorID: configuration.connectorID,
            modelID: configuration.modelID,
            parserError: output.parserError,
            parserText: output.text,
            rawOutput: output.raw,
            processError: output.processError
        ) {
            throw failure
        }
        guard let answer = output.text, !answer.isEmpty else {
            throw AssistantFailure.emptyOutput(configuration.connectorID)
        }
        await channel.send(.response(
            entryID: UUID().uuidString,
            action: .appendText(answer, segmentID: nil, tokenCount: 0)
        ))
    }
}
