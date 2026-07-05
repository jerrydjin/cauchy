import Foundation

enum GeminiSSETextAccumulator {
    static func accumulateText(from bytes: URLSession.AsyncBytes) async throws -> String {
        var previousText = ""
        var accumulated = ""
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
                  let delta = extractText(from: json)
            else { continue }

            if delta.hasPrefix(previousText) {
                accumulated = delta
                previousText = delta
            } else {
                accumulated += delta
                previousText = accumulated
            }
        }

        return accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
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
}
