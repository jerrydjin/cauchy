import Foundation
import FoundationModels

/// macOS 27 reference indexing through `LanguageModelSession`, including the
/// on-device model, a cloud `LanguageModel`, or a CLI adapter. Earlier systems
/// never construct this type.
@available(macOS 27, *)
struct SessionReferenceIndexModel: ReferenceIndexModel {
    let languageModel: any LanguageModel
    let vision: CloudReferenceIndexClient?

    var cloudVision: CloudReferenceIndexClient? { vision }

    var limitsConcurrency: Bool {
        languageModel is SystemLanguageModel || languageModel is CLIIndexLanguageModel
    }

    var provenanceName: String {
        if let cloud = languageModel as? CloudLanguageModel {
            return cloud.provider.rawValue
        }
        if languageModel is SystemLanguageModel {
            return "on-device"
        }
        return "cli"
    }

    var systemModel: SystemLanguageModel? {
        languageModel as? SystemLanguageModel
    }

    func complete(instructions: String, prompt: String) async throws -> String {
        try await completeOnMain(instructions: instructions, prompt: prompt)
    }

    @MainActor
    private func completeOnMain(instructions: String, prompt: String) async throws -> String {
        let session = LanguageModelSession(model: languageModel, instructions: instructions)
        let stream = session.streamResponse(to: prompt)
        var accumulated = ""
        for try await snapshot in stream {
            accumulated = snapshot.content
        }
        return accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@available(macOS 27, *)
enum ReferenceIndexModelFactory {
    static func sessionCloud(_ selection: CloudModelSelection) -> SessionReferenceIndexModel {
        SessionReferenceIndexModel(
            languageModel: CloudLanguageModel(
                provider: selection.provider,
                apiKey: selection.apiKey,
                modelName: selection.modelName
            ),
            vision: selection.client
        )
    }

    static func onDevice() -> SessionReferenceIndexModel {
        SessionReferenceIndexModel(languageModel: SystemLanguageModel.default, vision: nil)
    }
}
