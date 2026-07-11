import Foundation

enum GeminiSSETextAccumulator {
    static func accumulateText(from bytes: URLSession.AsyncBytes) async throws -> String {
        var accumulated = ""

        for try await line in bytes.lines {
            guard let delta = GeminiSSEParsing.textDelta(fromLine: line) else { continue }

            // The API usually sends true deltas, but tolerate cumulative
            // payloads too. The length guard keeps the common delta path from
            // prefix-comparing the whole accumulated text on every chunk.
            if delta.utf8.count >= accumulated.utf8.count, delta.hasPrefix(accumulated) {
                accumulated = delta
            } else {
                accumulated += delta
            }
        }

        return accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
