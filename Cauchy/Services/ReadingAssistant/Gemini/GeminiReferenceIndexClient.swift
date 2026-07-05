import Foundation

struct GeminiReferenceIndexClient: Sendable {
    let apiKey: String
    let modelName: String

    init(apiKey: String, modelName: String = GeminiCloudLanguageModel.defaultModelName) {
        self.apiKey = apiKey
        self.modelName = modelName
    }

    func indexPage(imagePNG: Data, pageText: String, pageIndex: Int) async throws -> String {
        let prompt = ReferenceIndexPromptBuilder.visionUserPrompt(pageText: pageText, pageIndex: pageIndex)
        let body = makeRequestBody(
            prompt: prompt,
            imagePNG: imagePNG,
            instructions: ReferenceIndexPromptBuilder.visionInstructions
        )
        return try await streamGenerateContent(body: body)
    }

    func repairJSON(previousOutput: String) async throws -> String {
        let body = makeRequestBody(
            prompt: ReferenceIndexPromptBuilder.jsonRepairPrompt(previousOutput: previousOutput),
            imagePNG: nil,
            instructions: ReferenceIndexPromptBuilder.instructions
        )
        return try await streamGenerateContent(body: body)
    }

    func repairLaTeX(previousOutput: String) async throws -> String {
        let body = makeRequestBody(
            prompt: ReadingPromptBuilder.latexRepairPrompt(previousOutput: previousOutput),
            imagePNG: nil,
            instructions: ReadingPromptBuilder.latexRepairInstructions()
        )
        return try await streamGenerateContent(body: body)
    }

    private func makeRequestBody(
        prompt: String,
        imagePNG: Data?,
        instructions: String
    ) -> [String: Any] {
        var parts: [[String: Any]] = []
        if let imagePNG {
            parts.append([
                "inline_data": [
                    "mime_type": "image/png",
                    "data": imagePNG.base64EncodedString(),
                ],
            ])
        }
        parts.append(["text": prompt])

        return [
            "systemInstruction": [
                "parts": [["text": instructions]],
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": parts,
                ],
            ],
        ]
    }

    private func streamGenerateContent(body: [String: Any]) async throws -> String {
        let requestData = try JSONSerialization.data(withJSONObject: body)
        let url = URL(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):streamGenerateContent?alt=sse"
        )!

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
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
            let message = GeminiSSETextAccumulator.parseErrorMessage(from: errorData) ?? "HTTP \(httpResponse.statusCode)"
            throw GeminiCloudAPIError.api(message)
        }

        return try await GeminiSSETextAccumulator.accumulateText(from: bytes)
    }
}
