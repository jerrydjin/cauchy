import Foundation
import FoundationModels
import PDFKit

enum ReferenceIndexBuildError: LocalizedError {
    case documentUnavailable

    var errorDescription: String? {
        switch self {
        case .documentUnavailable:
            "Could not read the PDF for reference indexing."
        }
    }
}

struct LLMPageReferenceResponse: Decodable, Equatable {
    struct Item: Decodable, Equatable {
        let kind: String
        let number: String
        let formattedBody: String

        enum CodingKeys: String, CodingKey {
            case kind
            case number
            case formattedBody = "formatted_body"
        }
    }

    let references: [Item]
}

enum LLMReferenceIndexResponseParser {
    static func parse(_ raw: String) throws -> LLMPageReferenceResponse {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = candidateJSONStrings(from: trimmed)

        var lastError: Error?
        for candidate in candidates {
            guard let data = candidate.data(using: .utf8) else { continue }
            do {
                return try JSONDecoder().decode(LLMPageReferenceResponse.self, from: data)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? ParserError.noJSONObjectFound
    }

    enum ParserError: Error {
        case noJSONObjectFound
    }

    private static func candidateJSONStrings(from text: String) -> [String] {
        var candidates: [String] = []
        if text.hasPrefix("{") {
            candidates.append(text)
        }

        if let regex = try? NSRegularExpression(pattern: #"\{[\s\S]*\}"#) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)
            for match in matches.reversed() {
                guard let jsonRange = Range(match.range, in: text) else { continue }
                candidates.append(String(text[jsonRange]))
            }
        }

        let normalized = AssistantResponseNormalizer.normalize(text)
        if normalized != text, normalized.hasPrefix("{") {
            candidates.append(normalized)
        }

        return Array(Set(candidates))
    }
}

struct PageIndexPayload: Sendable {
    let pageText: String
    let pageImagePNG: Data?
}

enum LLMReferenceIndexSupport {
    static func preprocessPageText(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return LaTeXFormatter.format(trimmed)
    }

    static func shouldUseVision(geminiVisionAvailable: Bool, pageImagePNG: Data?) -> Bool {
        geminiVisionAvailable && pageImagePNG != nil
    }

    /// Returns display-ready body, optionally using one repaired candidate.
    static func finalizeReferenceBody(normalized: String, repaired: String?) -> String? {
        if ReferenceFormattingHeuristics.isMostlyValidLaTeX(normalized) {
            return normalized
        }

        guard let repaired else { return nil }
        let fixed = AssistantResponseNormalizer.normalize(repaired)
        guard !fixed.isEmpty, ReferenceFormattingHeuristics.isMostlyValidLaTeX(fixed) else {
            return nil
        }
        return fixed
    }

    static func merge(
        _ indexed: IndexedReference,
        into results: inout [ReferenceKey: IndexedReference]
    ) {
        let key = indexed.reference.key
        if let existing = results[key] {
            if indexed.formattedBody.count > existing.formattedBody.count {
                results[key] = indexed
            }
        } else {
            results[key] = indexed
        }
    }
}

enum LLMReferenceIndexBuilder {
    static let maxConcurrentPages = 4

    private struct ModelHandle: Sendable {
        let model: any LanguageModel
        let geminiVision: GeminiReferenceIndexClient?
    }

    nonisolated static func build(
        documentURL: URL,
        model: any LanguageModel,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> DocumentReferenceIndexSnapshot {
        let fingerprint = try ReferenceIndexCacheStore.fingerprint(for: documentURL)

        guard let document = PDFDocument(url: documentURL) else {
            throw ReferenceIndexBuildError.documentUnavailable
        }

        if let cached = try? ReferenceIndexCacheStore.load(fingerprint: fingerprint) {
            return cached.asSnapshot(pageCount: document.pageCount)
        }

        let geminiVision: GeminiReferenceIndexClient?
        if let apiKey = KeychainService.loadGeminiAPIKey() {
            geminiVision = GeminiReferenceIndexClient(apiKey: apiKey)
        } else {
            geminiVision = nil
        }

        let modelHandle = ModelHandle(model: model, geminiVision: geminiVision)

        let pageCount = document.pageCount
        var merged: [ReferenceKey: IndexedReference] = [:]

        for batchStart in stride(from: 0, to: pageCount, by: maxConcurrentPages) {
            let batchEnd = min(batchStart + maxConcurrentPages, pageCount)
            try await withThrowingTaskGroup(of: (Int, [ReferenceKey: IndexedReference]).self) { group in
                for pageIndex in batchStart..<batchEnd {
                    let payload = pagePayload(from: document, pageIndex: pageIndex, geminiVision: geminiVision)
                    group.addTask {
                        let entries = try await processPage(
                            payload: payload,
                            pageIndex: pageIndex,
                            modelHandle: modelHandle
                        )
                        return (pageIndex, entries)
                    }
                }

                for try await (pageIndex, entries) in group {
                    progress?(pageIndex + 1, pageCount)
                    for (key, entry) in entries {
                        if let existing = merged[key] {
                            if entry.formattedBody.count > existing.formattedBody.count {
                                merged[key] = entry
                            }
                        } else {
                            merged[key] = entry
                        }
                    }
                }
            }
        }

        let snapshot = DocumentReferenceIndexSnapshot(entries: merged, pageCount: pageCount)
        let persisted = PersistedReferenceIndex(
            documentFingerprint: fingerprint,
            builtAt: Date(),
            entries: merged
        )
        try ReferenceIndexCacheStore.save(persisted)
        return snapshot
    }

    nonisolated private static func pagePayload(
        from document: PDFDocument,
        pageIndex: Int,
        geminiVision: GeminiReferenceIndexClient?
    ) -> PageIndexPayload {
        guard let page = document.page(at: pageIndex) else {
            return PageIndexPayload(pageText: "", pageImagePNG: nil)
        }

        let rawText = fullPageText(from: page)
        let pageText = LLMReferenceIndexSupport.preprocessPageText(rawText)

        var pageImagePNG: Data?
        if geminiVision != nil,
           let image = PDFRegionRenderer.renderFullPage(page),
           let png = PDFRegionRenderer.pngData(from: image) {
            pageImagePNG = png
        }

        return PageIndexPayload(pageText: pageText, pageImagePNG: pageImagePNG)
    }

    nonisolated private static func processPage(
        payload: PageIndexPayload,
        pageIndex: Int,
        modelHandle: ModelHandle
    ) async throws -> [ReferenceKey: IndexedReference] {
        let trimmedPageText = payload.pageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPageText.isEmpty else {
            return [:]
        }

        let rawResponse: String
        do {
            rawResponse = try await requestPageExtraction(
                payload: payload,
                pageIndex: pageIndex,
                modelHandle: modelHandle
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return [:]
        }

        guard let parsed = await parsePageResponse(
            rawResponse,
            modelHandle: modelHandle
        ) else {
            return [:]
        }

        var results: [ReferenceKey: IndexedReference] = [:]
        for item in parsed.references {
            let trimmedBody = item.formattedBody.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedBody.isEmpty else { continue }
            guard let kind = ReferenceKind(rawValue: item.kind.lowercased()) else { continue }

            let normalized = AssistantResponseNormalizer.normalize(trimmedBody)
            guard !normalized.isEmpty else { continue }

            let repaired = await repairLaTeXOnceIfNeeded(normalized, modelHandle: modelHandle)
            guard let formattedBody = LLMReferenceIndexSupport.finalizeReferenceBody(
                normalized: normalized,
                repaired: repaired
            ) else {
                continue
            }

            let indexed = IndexedReference(
                reference: DetectedReference(kind: kind, number: item.number),
                formattedBody: formattedBody,
                pageIndex: pageIndex
            )
            LLMReferenceIndexSupport.merge(indexed, into: &results)
        }

        return results
    }

    nonisolated private static func parsePageResponse(
        _ rawResponse: String,
        modelHandle: ModelHandle
    ) async -> LLMPageReferenceResponse? {
        if let parsed = try? LLMReferenceIndexResponseParser.parse(rawResponse) {
            return parsed
        }

        do {
            let repaired = try await requestJSONRepair(
                previousOutput: rawResponse,
                modelHandle: modelHandle
            )
            return try? LLMReferenceIndexResponseParser.parse(repaired)
        } catch {
            return nil
        }
    }

    nonisolated private static func repairLaTeXOnceIfNeeded(
        _ normalized: String,
        modelHandle: ModelHandle
    ) async -> String? {
        guard !ReferenceFormattingHeuristics.isMostlyValidLaTeX(normalized) else {
            return nil
        }

        do {
            return try await requestLaTeXRepair(
                previousOutput: normalized,
                modelHandle: modelHandle
            )
        } catch {
            return nil
        }
    }

    nonisolated private static func requestPageExtraction(
        payload: PageIndexPayload,
        pageIndex: Int,
        modelHandle: ModelHandle
    ) async throws -> String {
        if LLMReferenceIndexSupport.shouldUseVision(
            geminiVisionAvailable: modelHandle.geminiVision != nil,
            pageImagePNG: payload.pageImagePNG
        ),
           let geminiVision = modelHandle.geminiVision,
           let imagePNG = payload.pageImagePNG {
            return try await geminiVision.indexPage(
                imagePNG: imagePNG,
                pageText: payload.pageText,
                pageIndex: pageIndex
            )
        }

        return try await requestTextPageExtraction(
            pageText: payload.pageText,
            pageIndex: pageIndex,
            modelHandle: modelHandle
        )
    }

    @MainActor
    private static func requestTextPageExtraction(
        pageText: String,
        pageIndex: Int,
        modelHandle: ModelHandle
    ) async throws -> String {
        let session = LanguageModelSession(
            model: modelHandle.model,
            instructions: ReferenceIndexPromptBuilder.instructions
        )
        let prompt = ReferenceIndexPromptBuilder.userPrompt(pageText: pageText, pageIndex: pageIndex)
        return try await streamResponse(session: session, prompt: prompt)
    }

    nonisolated private static func requestJSONRepair(
        previousOutput: String,
        modelHandle: ModelHandle
    ) async throws -> String {
        if let geminiVision = modelHandle.geminiVision {
            return try await geminiVision.repairJSON(previousOutput: previousOutput)
        }

        return try await requestTextJSONRepair(
            previousOutput: previousOutput,
            modelHandle: modelHandle
        )
    }

    @MainActor
    private static func requestTextJSONRepair(
        previousOutput: String,
        modelHandle: ModelHandle
    ) async throws -> String {
        let session = LanguageModelSession(
            model: modelHandle.model,
            instructions: ReferenceIndexPromptBuilder.instructions
        )
        let prompt = ReferenceIndexPromptBuilder.jsonRepairPrompt(previousOutput: previousOutput)
        return try await streamResponse(session: session, prompt: prompt)
    }

    nonisolated private static func requestLaTeXRepair(
        previousOutput: String,
        modelHandle: ModelHandle
    ) async throws -> String {
        if let geminiVision = modelHandle.geminiVision {
            return try await geminiVision.repairLaTeX(previousOutput: previousOutput)
        }

        return try await requestTextLaTeXRepair(
            previousOutput: previousOutput,
            modelHandle: modelHandle
        )
    }

    @MainActor
    private static func requestTextLaTeXRepair(
        previousOutput: String,
        modelHandle: ModelHandle
    ) async throws -> String {
        let session = LanguageModelSession(
            model: modelHandle.model,
            instructions: ReadingPromptBuilder.latexRepairInstructions()
        )
        let prompt = ReadingPromptBuilder.latexRepairPrompt(previousOutput: previousOutput)
        return try await streamResponse(session: session, prompt: prompt)
    }

    @MainActor
    private static func streamResponse(session: LanguageModelSession, prompt: String) async throws -> String {
        let stream = session.streamResponse(to: prompt)
        var accumulated = ""
        for try await snapshot in stream {
            accumulated = snapshot.content
        }
        return accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func fullPageText(from page: PDFPage) -> String {
        let bounds = page.bounds(for: .mediaBox)
        return page.selection(for: bounds)?.string ?? ""
    }
}
