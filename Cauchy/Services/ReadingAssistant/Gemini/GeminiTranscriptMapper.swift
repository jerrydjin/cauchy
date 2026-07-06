import Foundation
import FoundationModels

enum GeminiTranscriptMapper {
    static func makeRequestBody(from transcript: Transcript) -> [String: Any] {
        var systemInstruction: String?
        var contents: [[String: Any]] = []

        for entry in transcript {
            switch entry {
            case .instructions(let instructions):
                systemInstruction = text(from: instructions.segments)
            case .prompt(let prompt):
                if let text = text(from: prompt.segments), !text.isEmpty {
                    contents.append([
                        "role": "user",
                        "parts": [["text": text]],
                    ])
                }
            case .response(let response):
                if let text = text(from: response.segments), !text.isEmpty {
                    contents.append([
                        "role": "model",
                        "parts": [["text": text]],
                    ])
                }
            case .reasoning, .toolCalls, .toolOutput:
                break // We don't support reasoning or tools natively yet in this mapper
            @unknown default:
                break
            }
        }

        var body: [String: Any] = ["contents": contents]
        if let systemInstruction, !systemInstruction.isEmpty {
            body["systemInstruction"] = [
                "parts": [["text": systemInstruction]],
            ]
        }
        return body
    }

    private static func text(from segments: [Transcript.Segment]) -> String? {
        let parts = segments.compactMap { segment -> String? in
            guard case .text(let textSegment) = segment else { return nil }
            return textSegment.content
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined()
    }
}
