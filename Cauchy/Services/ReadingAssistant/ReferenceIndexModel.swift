import Foundation

/// One page-extraction backend. macOS 27 wraps FoundationModels; earlier
/// systems call a cloud API or a CLI directly, or read the PDF text only.
protocol ReferenceIndexModel: Sendable {
    var cloudVision: CloudReferenceIndexClient? { get }
    /// On-device and CLI jobs are serialized. Cloud HTTP is not.
    var limitsConcurrency: Bool { get }
    /// Recorded on the index when the caller did not pass its own description.
    var provenanceName: String { get }
    /// False for the PDF-text index used when no model is configured.
    var usesLanguageModel: Bool { get }
    func complete(instructions: String, prompt: String) async throws -> String
}

extension ReferenceIndexModel {
    var cloudVision: CloudReferenceIndexClient? { nil }
    var limitsConcurrency: Bool { false }
    var usesLanguageModel: Bool { true }
}

/// Builds hover previews from the PDF text layer (and OCR candidates) without
/// calling a model. Declarations the heuristics can see still preview.
struct SourceOnlyReferenceIndexModel: ReferenceIndexModel {
    var usesLanguageModel: Bool { false }
    var provenanceName: String { "PDF text" }

    func complete(instructions: String, prompt: String) async throws -> String {
        throw ReferenceIndexBuildError.unparseableResponse
    }
}

struct DirectCloudReferenceIndexModel: ReferenceIndexModel {
    let client: CloudReferenceIndexClient

    var cloudVision: CloudReferenceIndexClient? { client }
    var provenanceName: String { client.provider.rawValue }

    func complete(instructions: String, prompt: String) async throws -> String {
        try await CloudStreamingClient.text(
            provider: client.provider,
            apiKey: client.apiKey,
            modelName: client.modelName,
            prompt: CloudPrompt(instructions: instructions, prompt: prompt)
        )
    }
}

struct DirectCLIReferenceIndexModel: ReferenceIndexModel {
    let connectorID: AssistantConnectorID
    let modelID: String?

    var limitsConcurrency: Bool { true }
    var provenanceName: String { connectorID.connector.name }

    func complete(instructions: String, prompt: String) async throws -> String {
        try await CLIIndexRunner.complete(
            connectorID: connectorID,
            modelID: modelID,
            instructions: instructions,
            prompt: prompt
        )
    }
}

enum CloudKeyAvailability {
    static func availability(for provider: CloudAPIProvider) -> ReadingAssistantAvailability {
        KeychainService.hasKey(for: provider)
            ? .available(provider.connectorID)
            : .apiKeyMissing(provider)
    }
}

/// A saved key plus the model name to call. Available on every supported OS;
/// the FoundationModels adapter is built from this only on macOS 27.
struct CloudModelSelection: Sendable {
    let provider: CloudAPIProvider
    let apiKey: String
    let modelName: String

    var client: CloudReferenceIndexClient {
        CloudReferenceIndexClient(provider: provider, apiKey: apiKey, modelName: modelName)
    }
}
