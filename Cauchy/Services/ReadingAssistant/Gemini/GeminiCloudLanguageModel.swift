import Foundation
import FoundationModels

struct GeminiCloudLanguageModel: LanguageModel {
    typealias Executor = GeminiCloudLanguageModelExecutor

    static let defaultModelName = "gemini-3.5-flash"

    let apiKey: String
    let modelName: String

    init(apiKey: String, modelName: String = defaultModelName) {
        self.apiKey = apiKey
        self.modelName = modelName
    }

    var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities(capabilities: [])
    }

    var executorConfiguration: GeminiCloudLanguageModelExecutor.Configuration {
        GeminiCloudLanguageModelExecutor.Configuration(
            apiKey: apiKey,
            modelName: modelName
        )
    }
}
