import Foundation
import FoundationModels

@MainActor
final class FoundationModelsReadingAssistantService: ReadingAssistantProtocol {
    let provider: AssistantConnectorID

    private let model: any LanguageModel
    private var session: LanguageModelSession?

    init(model: any LanguageModel, provider: AssistantConnectorID) {
        self.model = model
        self.provider = provider
    }

    static var localAvailability: ReadingAssistantAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available(.onDevice)
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .intelligenceNotEnabled
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    static func availability(for apiProvider: CloudAPIProvider) -> ReadingAssistantAvailability {
        KeychainService.hasKey(for: apiProvider)
            ? .available(apiProvider.connectorID)
            : .apiKeyMissing(apiProvider)
    }

    var availability: ReadingAssistantAvailability {
        guard let apiProvider = provider.connector.apiProvider else {
            return Self.localAvailability
        }
        return Self.availability(for: apiProvider)
    }

    private var isAvailable: Bool {
        if let apiProvider = provider.connector.apiProvider {
            return KeychainService.hasKey(for: apiProvider)
        }
        guard let systemModel = model as? SystemLanguageModel else { return false }
        return systemModel.isAvailable
    }

    var isResponding: Bool {
        session?.isResponding ?? false
    }

    func resetSession(context: ReadingContext) {
        session = LanguageModelSession(
            model: model,
            instructions: ReadingPromptBuilder.instructions(for: context, provider: provider)
        )
    }

    func restoreSession(context: ReadingContext, messages: [ThreadMessage]) {
        let instructionText = ReadingPromptBuilder.instructions(for: context, provider: provider)
        let instructionsEntry = Transcript.Entry.instructions(
            Transcript.Instructions(
                segments: [.text(Transcript.TextSegment(content: instructionText))],
                toolDefinitions: []
            )
        )

        var entries: [Transcript.Entry] = [instructionsEntry]
        for message in messages {
            switch message.role {
            case .user:
                entries.append(.prompt(
                    Transcript.Prompt(segments: [.text(Transcript.TextSegment(content: message.content))])
                ))
            case .assistant:
                entries.append(.response(
                    Transcript.Response(
                        assetIDs: [],
                        segments: [.text(Transcript.TextSegment(content: message.content))]
                    )
                ))
            }
        }

        session = LanguageModelSession(model: model, transcript: Transcript(entries: entries))
    }

    func ask(
        question: String,
        retrieval: AskRetrieval,
        onPartial: ((String) -> Void)? = nil
    ) async throws -> String {
        guard isAvailable else {
            throw ReadingAssistantError.notAvailable(availability)
        }
        guard let session else {
            throw ReadingAssistantError.sessionUnavailable
        }
        guard !session.isResponding else {
            throw ReadingAssistantError.sessionBusy
        }

        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Retrieval rides the per-turn prompt (sessions fix their instructions
        // at reset/restore time). Exact statements come first and get priority
        // budget; both budgets stay small enough for the local window.
        var prompt = trimmed
        let statementBudget = provider == .onDevice ? 1_200 : 2_500
        let passageBudget = provider == .onDevice ? 800 : 4_000
        var blocks: [String] = []
        if let block = ReadingPromptBuilder.referencedStatementsBlock(retrieval.statements, characterBudget: statementBudget) {
            blocks.append(block)
        }
        if let block = ReadingPromptBuilder.retrievedPassagesBlock(retrieval.passages, characterBudget: passageBudget) {
            blocks.append(block)
        }
        if !blocks.isEmpty {
            prompt = blocks.joined(separator: "\n\n") + "\n\nQUESTION: " + trimmed
        }

        do {
            let stream = session.streamResponse(to: prompt)
            var accumulated = ""
            for try await snapshot in stream {
                accumulated = snapshot.content
                onPartial?(AssistantResponseNormalizer.normalize(accumulated))
            }

            let normalized = AssistantResponseNormalizer.normalize(accumulated)
            let final = try await ensureDisplayReady(normalized, onPartial: onPartial)
            onPartial?(final)
            return final
        } catch let error as CloudAPIError {
            throw Self.mapCloudError(error)
        } catch let error as LanguageModelError {
            throw ReadingAssistantError.languageModel(error)
        }
    }

    private func ensureDisplayReady(
        _ text: String,
        onPartial: ((String) -> Void)? = nil
    ) async throws -> String {
        guard !AssistantResponseValidator.isDisplayReady(text) else { return text }

        let repairSession = LanguageModelSession(
            model: model,
            instructions: ReadingPromptBuilder.latexRepairInstructions()
        )
        let stream = repairSession.streamResponse(
            to: ReadingPromptBuilder.latexRepairPrompt(previousOutput: text)
        )

        var repaired = ""
        for try await snapshot in stream {
            repaired = snapshot.content
            onPartial?(AssistantResponseNormalizer.normalize(repaired))
        }

        let normalized = AssistantResponseNormalizer.normalize(repaired)
        return AssistantResponseValidator.isDisplayReady(normalized) ? normalized : text
    }

    static func mapCloudError(_ error: CloudAPIError) -> ReadingAssistantError {
        switch error {
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
