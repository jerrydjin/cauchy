import Foundation

/// BYOK chat without FoundationModels. Used below macOS 27 so an API key still
/// answers questions. On macOS 27 the app keeps using `LanguageModelSession`.
@MainActor
final class DirectCloudReadingAssistantService: ReadingAssistantProtocol {
    let provider: AssistantConnectorID

    private let apiProvider: CloudAPIProvider
    private let apiKey: String
    private let modelName: String
    private var instructions = ""
    private var history: [ThreadMessage] = []
    private(set) var isResponding = false

    init(
        provider: AssistantConnectorID,
        apiProvider: CloudAPIProvider,
        apiKey: String,
        modelName: String?
    ) {
        self.provider = provider
        self.apiProvider = apiProvider
        self.apiKey = apiKey
        self.modelName = modelName ?? apiProvider.defaultModelID
    }

    var availability: ReadingAssistantAvailability {
        CloudKeyAvailability.availability(for: apiProvider)
    }

    func resetSession(context: ReadingContext) {
        instructions = ReadingPromptBuilder.instructions(for: context, provider: provider)
        history = []
    }

    func restoreSession(context: ReadingContext, messages: [ThreadMessage]) {
        instructions = ReadingPromptBuilder.instructions(for: context, provider: provider)
        history = messages
    }

    func ask(
        question: String,
        retrieval: AskRetrieval,
        onPartial: ((String) -> Void)? = nil
    ) async throws -> String {
        guard !isResponding else {
            throw ReadingAssistantError.sessionBusy
        }
        guard CloudKeyAvailability.availability(for: apiProvider).isAvailable else {
            throw ReadingAssistantError.notAvailable(availability)
        }

        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var prompt = trimmed
        let budgets = ReadingPromptBuilder.evidenceBudgets(for: provider)
        var blocks: [String] = []
        if let block = ReadingPromptBuilder.referencedStatementsBlock(retrieval.statements, characterBudget: budgets.statements) {
            blocks.append(block)
        }
        if let block = ReadingPromptBuilder.retrievedPassagesBlock(retrieval.passages, characterBudget: budgets.passages) {
            blocks.append(block)
        }
        if let block = ReadingPromptBuilder.citableSourcesBlock(retrieval.citableSources) {
            blocks.append(block)
        }
        if !blocks.isEmpty {
            prompt = blocks.joined(separator: "\n\n") + "\n\nQUESTION: " + trimmed
        }

        isResponding = true
        defer { isResponding = false }

        do {
            var turns = history.map { message in
                CloudPrompt.Turn(
                    role: message.role == .user ? .user : .assistant,
                    text: message.content
                )
            }
            turns.append(CloudPrompt.Turn(role: .user, text: prompt))
            let cloudPrompt = CloudPrompt(instructions: instructions, turns: turns)

            // `stream`'s callback is main-actor isolated here and cannot be sent
            // into that concurrent method. The text client accumulates off the
            // actor; the ask field updates when the answer is complete.
            let accumulated = try await CloudStreamingClient.text(
                provider: apiProvider,
                apiKey: apiKey,
                modelName: modelName,
                prompt: cloudPrompt
            )
            let normalized = AssistantResponseNormalizer.normalize(accumulated)
            let final = try await ensureDisplayReady(normalized, onPartial: onPartial)
            onPartial?(final)
            history.append(ThreadMessage(role: .user, content: prompt))
            history.append(ThreadMessage(role: .assistant, content: final))
            return final
        } catch let error as CloudAPIError {
            throw error.asReadingAssistantError
        }
    }

    private func ensureDisplayReady(
        _ text: String,
        onPartial: ((String) -> Void)?
    ) async throws -> String {
        guard !AssistantResponseValidator.isDisplayReady(text) else { return text }

        let repaired = try await CloudStreamingClient.text(
            provider: apiProvider,
            apiKey: apiKey,
            modelName: modelName,
            prompt: CloudPrompt(
                instructions: ReadingPromptBuilder.latexRepairInstructions(),
                prompt: ReadingPromptBuilder.latexRepairPrompt(previousOutput: text)
            )
        )
        let normalized = AssistantResponseNormalizer.normalize(repaired)
        let chosen = AssistantResponseValidator.isDisplayReady(normalized) ? normalized : text
        onPartial?(chosen)
        return chosen
    }
}

extension CloudAPIError {
    var asReadingAssistantError: ReadingAssistantError {
        switch self {
        case .invalidAPIKey(let provider):
            return .invalidAPIKey(provider)
        case .rateLimited(let provider):
            return .rateLimited(provider)
        case .network(let message):
            return .network(message)
        case .api(let message):
            return .api(message)
        }
    }
}
