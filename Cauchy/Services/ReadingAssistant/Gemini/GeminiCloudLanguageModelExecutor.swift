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
            let message = Self.parseErrorMessage(from: errorData) ?? "HTTP \(httpResponse.statusCode)"
            throw GeminiCloudAPIError.api(message)
        }

        var previousText = ""
        var lineBuffer = Data()

        for try await byte in bytes {
            lineBuffer.append(byte)

            guard byte == UInt8(ascii: "\n") else { continue }
            defer { lineBuffer.removeAll(keepingCapacity: true) }

            guard let line = String(data: lineBuffer.dropLast(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !line.isEmpty
            else { continue }

            guard line.hasPrefix("data:") else { continue }
            let jsonString = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard !jsonString.isEmpty, jsonString != "[DONE]" else { continue }

            guard let jsonData = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let delta = Self.extractText(from: json)
            else { continue }

            let incremental: String
            if delta.hasPrefix(previousText) {
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

    private static func extractText(from json: [String: Any]) -> String? {
        guard let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]]
        else { return nil }

        let textParts = parts.compactMap { part -> String? in
            if part["thought"] as? Bool == true { return nil }
            return part["text"] as? String
        }
        guard !textParts.isEmpty else { return nil }
        return textParts.joined()
    }

    private static func parseErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return nil
    }
}
