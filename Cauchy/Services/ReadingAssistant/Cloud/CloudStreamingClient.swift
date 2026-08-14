import Foundation

/// The one place a BYOK provider is actually called over the network: build the
/// request from its wire format, map HTTP status to a typed error, and hand
/// back the text as it arrives. Chat and reference indexing both go through
/// this, so a new provider needs no transport code of its own.
enum CloudStreamingClient {
    /// Streams the answer, invoking `onDelta` with each new fragment.
    static func stream(
        provider: CloudAPIProvider,
        apiKey: String,
        modelName: String,
        prompt: CloudPrompt,
        onDelta: (String) async -> Void
    ) async throws {
        let wire = provider.wire
        let request = try wire.urlRequest(apiKey: apiKey, modelName: modelName, prompt: prompt)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudAPIError.network("Invalid response.")
        }

        // 401 and 403 both mean the key: missing/typo'd, or valid but without
        // access to this model. Either way the user's fix is in Settings.
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw CloudAPIError.invalidAPIKey(provider)
        }
        if httpResponse.statusCode == 429 {
            throw CloudAPIError.rateLimited(provider)
        }
        if httpResponse.statusCode >= 400 {
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
            }
            let message = wire.errorMessage(from: errorData) ?? "HTTP \(httpResponse.statusCode)"
            throw CloudAPIError.api(message)
        }

        var coalescer = DeltaCoalescer()
        for try await line in bytes.lines {
            guard let delta = wire.textDelta(fromLine: line),
                  let incremental = coalescer.incremental(from: delta)
            else { continue }
            await onDelta(incremental)
        }
    }

    /// Streams to completion and returns the whole answer — for the jobs
    /// (indexing, repair, titling) with nothing to show mid-flight.
    static func text(
        provider: CloudAPIProvider,
        apiKey: String,
        modelName: String,
        prompt: CloudPrompt
    ) async throws -> String {
        var accumulated = ""
        try await stream(
            provider: provider,
            apiKey: apiKey,
            modelName: modelName,
            prompt: prompt
        ) { delta in
            accumulated += delta
        }
        return accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Turns whatever a provider sends into strict deltas.
///
/// All three APIs document incremental chunks, but Gemini has been seen to send
/// the accumulated text instead; a cumulative payload appended verbatim would
/// duplicate the whole answer. The length guard keeps the common delta path
/// from prefix-comparing the accumulated text on every chunk.
private struct DeltaCoalescer {
    private var previous = ""

    mutating func incremental(from chunk: String) -> String? {
        let incremental: String
        if chunk.utf8.count >= previous.utf8.count, chunk.hasPrefix(previous) {
            incremental = String(chunk.dropFirst(previous.count))
            previous = chunk
        } else {
            incremental = chunk
            previous += chunk
        }
        return incremental.isEmpty ? nil : incremental
    }
}
