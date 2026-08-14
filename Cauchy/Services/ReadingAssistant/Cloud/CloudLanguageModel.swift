import Foundation
import FoundationModels

/// A BYOK provider dressed as a `LanguageModel`, so everything built on
/// `LanguageModelSession` — chat, reference indexing, thread titles — works the
/// same whether the answer comes from this Mac or from a vendor's API.
struct CloudLanguageModel: LanguageModel {
    typealias Executor = CloudLanguageModelExecutor

    let provider: CloudAPIProvider
    let apiKey: String
    let modelName: String

    init(provider: CloudAPIProvider, apiKey: String, modelName: String? = nil) {
        self.provider = provider
        self.apiKey = apiKey
        self.modelName = modelName ?? provider.defaultModelID
    }

    var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities([])
    }

    var executorConfiguration: CloudLanguageModelExecutor.Configuration {
        CloudLanguageModelExecutor.Configuration(
            provider: provider,
            apiKey: apiKey,
            modelName: modelName
        )
    }
}

struct CloudLanguageModelExecutor: LanguageModelExecutor {
    typealias Model = CloudLanguageModel

    struct Configuration: Hashable, Sendable {
        let provider: CloudAPIProvider
        let apiKey: String
        let modelName: String
    }

    let configuration: Configuration

    init(configuration: Configuration) throws {
        self.configuration = configuration
    }

    func prewarm(model: CloudLanguageModel, transcript: Transcript) {}

    func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: CloudLanguageModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        let entryID = UUID().uuidString

        try await CloudStreamingClient.stream(
            provider: configuration.provider,
            apiKey: configuration.apiKey,
            modelName: configuration.modelName,
            prompt: CloudPrompt(transcript: request.transcript)
        ) { delta in
            await channel.send(.response(
                entryID: entryID,
                action: .appendText(delta, segmentID: nil, tokenCount: 0)
            ))
        }
    }
}
