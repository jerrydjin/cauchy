import Foundation
import FoundationModels

struct GeminiCloudLanguageModelExecutor: LanguageModelExecutor {
    typealias Model = GeminiCloudLanguageModel

    struct Configuration: Hashable, Sendable {
        let apiKey: String
        let modelName: String
    }

    let configuration: Configuration

    init(configuration: Configuration) throws {
        self.configuration = configuration
    }

    func prewarm(model: GeminiCloudLanguageModel, transcript: Transcript) {}

    func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: GeminiCloudLanguageModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        let entryID = UUID().uuidString
        let requestBody = GeminiTranscriptMapper.makeRequestBody(from: request.transcript)
        let requestData = try JSONSerialization.data(withJSONObject: requestBody)

        let url = URL(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(configuration.modelName):streamGenerateContent?alt=sse"
        )!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(configuration.apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.httpBody = requestData

        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiCloudAPIError.network("Invalid response.")
        }

        if httpResponse.statusCode == 401 {
            throw GeminiCloudAPIError.invalidAPIKey
        }
        if httpResponse.statusCode == 429 {
            throw GeminiCloudAPIError.rateLimited
        }
        if httpResponse.statusCode >= 400 {
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
            }
            let message = GeminiSSEParsing.parseErrorMessage(from: errorData) ?? "HTTP \(httpResponse.statusCode)"
            throw GeminiCloudAPIError.api(message)
        }

        var previousText = ""

        for try await line in bytes.lines {
            guard let delta = GeminiSSEParsing.textDelta(fromLine: line) else { continue }

            // The API usually sends true deltas, but tolerate cumulative
            // payloads too. The length guard keeps the common delta path from
            // prefix-comparing the whole accumulated text on every chunk.
            let incremental: String
            if delta.utf8.count >= previousText.utf8.count, delta.hasPrefix(previousText) {
                incremental = String(delta.dropFirst(previousText.count))
                previousText = delta
            } else {
                incremental = delta
                previousText += delta
            }

            guard !incremental.isEmpty else { continue }

            await channel.send(.response(
                entryID: entryID,
                action: .appendText(incremental, segmentID: nil, tokenCount: 0)
            ))
        }
    }
}
