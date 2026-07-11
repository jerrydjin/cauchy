import Foundation

/// Shared parsing for Gemini `streamGenerateContent?alt=sse` responses.
enum GeminiSSEParsing {
    /// Extracts the text payload from one SSE line, or nil for keep-alives,
    /// non-data lines, `[DONE]`, and thought-only chunks.
    static func textDelta(fromLine rawLine: String) -> String? {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, line.hasPrefix("data:") else { return nil }

        let jsonString = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard !jsonString.isEmpty, jsonString != "[DONE]" else { return nil }

        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else { return nil }

        return extractText(from: json)
    }

    static func extractText(from json: [String: Any]) -> String? {
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

    static func parseErrorMessage(from data: Data) -> String? {
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
