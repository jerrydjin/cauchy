import Foundation
import FoundationModels
import PDFKit

enum ReferenceIndexBuildError: LocalizedError {
    case documentUnavailable
    case unparseableResponse

    var errorDescription: String? {
        switch self {
        case .documentUnavailable:
            "Could not read the PDF for reference indexing."
        case .unparseableResponse:
            "The model's response could not be parsed."
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

    /// Table-of-contents pages list every "Definition 6.1"-style heading with a
    /// page number and no body; models (the on-device one especially) extract
    /// them as real references. Detect such pages structurally and skip the
    /// model call entirely.
    static func isLikelyTableOfContents(_ pageText: String) -> Bool {
        let lines = pageText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count >= 5 else { return false }

        let headerWords: Set<String> = ["contents", "table of contents", "index"]
        if lines.prefix(3).contains(where: { headerWords.contains($0.lowercased()) }) {
            return true
        }

        // "6.1. Compact spaces . . . . 34" — dot leaders or a numbered heading
        // that ends in a bare page number.
        let tocLike = lines.filter { line in
            line.range(of: #"(\.\s*){3,}\d+$"#, options: .regularExpression) != nil ||
                line.range(of: #"^\d+(\.\d+)*\.?\s+\D.*\s\d{1,3}$"#, options: .regularExpression) != nil
        }.count
        return tocLike >= 8 || Double(tocLike) / Double(lines.count) >= 0.4
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
    /// The system serializes on-device inference anyway; extra in-flight
    /// requests only queue up and risk timeouts.
    static let maxConcurrentPagesOnDevice = 2

    private struct ModelHandle: Sendable {
        let model: any LanguageModel
        let geminiVision: GeminiReferenceIndexClient?
    }

    struct BuildOutcome: Sendable {
        let snapshot: DocumentReferenceIndexSnapshot
        /// Pages that still failed after retries; persisted so the next open
        /// re-indexes only these.
        let failedPageIndices: [Int]
    }

    nonisolated static func build(
        documentURL: URL,
        model: any LanguageModel,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> BuildOutcome {
        let fingerprint = try ReferenceIndexCacheStore.fingerprint(for: documentURL)

        guard let document = PDFDocument(url: documentURL) else {
            throw ReferenceIndexBuildError.documentUnavailable
        }
        let pageCount = document.pageCount

        let cached = try? ReferenceIndexCacheStore.load(fingerprint: fingerprint)
        if let cached, cached.failedPageIndices.isEmpty {
            return BuildOutcome(snapshot: cached.asSnapshot(pageCount: pageCount), failedPageIndices: [])
        }

        // Vision (and its per-page PNG rendering) only when the chosen model
        // is actually Gemini — a saved API key alone must not spend API calls
        // when indexing runs on-device.
        let geminiVision: GeminiReferenceIndexClient?
        if let gemini = model as? GeminiCloudLanguageModel {
            geminiVision = GeminiReferenceIndexClient(apiKey: gemini.apiKey, modelName: gemini.modelName)
        } else {
            geminiVision = nil
        }

        let modelHandle = ModelHandle(model: model, geminiVision: geminiVision)

        // A cache with failed pages seeds the result and narrows the work to
        // just those pages; provenance stays with the original bulk build.
        var merged: [ReferenceKey: IndexedReference] = [:]
        var pagesToProcess = Array(0..<pageCount)
        var builtWith = model is GeminiCloudLanguageModel ? "gemini" : "on-device"
        if let cached {
            merged = cached.asSnapshot(pageCount: pageCount).entries
            pagesToProcess = cached.failedPageIndices.filter { $0 < pageCount }
            builtWith = cached.builtWith
        }

        let concurrency = (geminiVision == nil && model is SystemLanguageModel)
            ? maxConcurrentPagesOnDevice
            : maxConcurrentPages

        var failed: [Int] = []
        var completedCount = 0

        for batchStart in stride(from: 0, to: pagesToProcess.count, by: concurrency) {
            let batchEnd = min(batchStart + concurrency, pagesToProcess.count)
            try await withThrowingTaskGroup(of: (Int, [ReferenceKey: IndexedReference]?).self) { group in
                for pageIndex in pagesToProcess[batchStart..<batchEnd] {
                    let payload = pagePayload(from: document, pageIndex: pageIndex, geminiVision: geminiVision)
                    group.addTask {
                        do {
                            let entries = try await processPageWithRetry(
                                payload: payload,
                                pageIndex: pageIndex,
                                modelHandle: modelHandle
                            )
                            return (pageIndex, entries)
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            return (pageIndex, nil)
                        }
                    }
                }

                for try await (pageIndex, entries) in group {
                    completedCount += 1
                    progress?(completedCount, pagesToProcess.count)
                    guard let entries else {
                        failed.append(pageIndex)
                        continue
                    }
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
        failed.sort()

        // A mostly-failed fresh run points at a systemic outage — don't bake
        // it into the cache; the next open retries the whole document.
        let failureRate = pagesToProcess.isEmpty ? 0 : Double(failed.count) / Double(pagesToProcess.count)
        if cached != nil || failureRate <= 0.5 {
            let persisted = PersistedReferenceIndex(
                documentFingerprint: fingerprint,
                builtAt: Date(),
                entries: merged,
                builtWith: builtWith,
                failedPageIndices: failed
            )
            try? ReferenceIndexCacheStore.save(persisted)
        }
        return BuildOutcome(snapshot: snapshot, failedPageIndices: failed)
    }

    /// Retries transient per-page failures with backoff; rate limits wait
    /// longer. Context overflow is never retried — splitting already handled
    /// it, and a repeat attempt cannot do better.
    nonisolated private static func processPageWithRetry(
        payload: PageIndexPayload,
        pageIndex: Int,
        modelHandle: ModelHandle
    ) async throws -> [ReferenceKey: IndexedReference] {
        var attempt = 1
        while true {
            do {
                return try await processPage(payload: payload, pageIndex: pageIndex, modelHandle: modelHandle)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard attempt < 3, !isContextOverflow(error) else { throw error }
                let rateLimited = if let gemini = error as? GeminiCloudAPIError,
                                     case .rateLimited = gemini { true } else { false }
                let base: Double = rateLimited ? (attempt == 1 ? 5 : 15) : (attempt == 1 ? 1 : 4)
                try await Task.sleep(for: .seconds(base + Double.random(in: 0...0.5)))
                attempt += 1
            }
        }
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
        guard !trimmedPageText.isEmpty,
              !LLMReferenceIndexSupport.isLikelyTableOfContents(trimmedPageText) else {
            return [:]
        }

        let parsed = try await extractPageReferences(
            payload: payload,
            pageIndex: pageIndex,
            modelHandle: modelHandle
        )
        return await finalizeItems(parsed, pageIndex: pageIndex, modelHandle: modelHandle)
    }

    /// Normalizes, repairs, and validates the extracted items into indexable
    /// entries, dropping any whose LaTeX cannot be made display-ready.
    nonisolated private static func finalizeItems(
        _ parsed: LLMPageReferenceResponse,
        pageIndex: Int,
        modelHandle: ModelHandle
    ) async -> [ReferenceKey: IndexedReference] {
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

    // MARK: - Benchmark support

    struct SinglePageResult: Sendable {
        /// References the model returned before validation/repair.
        let parsedCount: Int
        /// Entries that survived normalization and LaTeX validation.
        let entries: [ReferenceKey: IndexedReference]
        let pageTextCharacters: Int
    }

    /// Runs the exact production extraction path for one page — used by the
    /// headless indexing benchmark. Errors propagate with full detail instead
    /// of being swallowed like in the bulk build.
    nonisolated static func indexSinglePage(
        from document: PDFDocument,
        pageIndex: Int,
        model: any LanguageModel
    ) async throws -> SinglePageResult {
        let handle = ModelHandle(model: model, geminiVision: nil)
        let payload = pagePayload(from: document, pageIndex: pageIndex, geminiVision: nil)
        let trimmed = payload.pageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !LLMReferenceIndexSupport.isLikelyTableOfContents(trimmed) else {
            return SinglePageResult(parsedCount: 0, entries: [:], pageTextCharacters: 0)
        }

        let parsed = try await extractPageReferences(
            payload: payload,
            pageIndex: pageIndex,
            modelHandle: handle
        )
        let entries = await finalizeItems(parsed, pageIndex: pageIndex, modelHandle: handle)
        return SinglePageResult(
            parsedCount: parsed.references.count,
            entries: entries,
            pageTextCharacters: trimmed.count
        )
    }

    /// Routes one page to the right extraction path: guided generation for the
    /// on-device model (schema-constrained, no JSON parsing), otherwise the
    /// raw-JSON text/vision path with parse repair.
    nonisolated private static func extractPageReferences(
        payload: PageIndexPayload,
        pageIndex: Int,
        modelHandle: ModelHandle
    ) async throws -> LLMPageReferenceResponse {
        if modelHandle.geminiVision == nil,
           let systemModel = modelHandle.model as? SystemLanguageModel {
            return try await requestGuidedPageExtraction(
                pageText: payload.pageText,
                pageIndex: pageIndex,
                model: systemModel
            )
        }

        let rawResponse = try await requestPageExtraction(
            payload: payload,
            pageIndex: pageIndex,
            modelHandle: modelHandle
        )
        guard let parsed = await parsePageResponse(rawResponse, modelHandle: modelHandle) else {
            throw ReferenceIndexBuildError.unparseableResponse
        }
        return parsed
    }

    @MainActor
    private static func requestGuidedPageExtraction(
        pageText: String,
        pageIndex: Int,
        model: SystemLanguageModel,
        depth: Int = 0
    ) async throws -> LLMPageReferenceResponse {
        let budgeted = String(pageText.prefix(ReferenceIndexPromptBuilder.maxPageCharactersOnDevice))
        do {
            let session = LanguageModelSession(
                model: model,
                instructions: ReferenceIndexPromptBuilder.onDeviceInstructions
            )
            let prompt = ReferenceIndexPromptBuilder.onDeviceUserPrompt(
                pageText: budgeted,
                pageIndex: pageIndex
            )
            let response = try await session.respond(to: prompt, generating: GeneratedPageReferences.self)
            return response.content.asResponse
        } catch {
            // Even a budgeted page can overflow the window once the schema and
            // generated output are counted; split at a paragraph boundary and
            // index each half separately.
            guard isContextOverflow(error), depth < 2, budgeted.count >= 1_000 else {
                throw error
            }
            let (head, tail) = splitNearMidpoint(budgeted)
            let first = try await requestGuidedPageExtraction(
                pageText: head, pageIndex: pageIndex, model: model, depth: depth + 1
            )
            let second = try await requestGuidedPageExtraction(
                pageText: tail, pageIndex: pageIndex, model: model, depth: depth + 1
            )
            return LLMPageReferenceResponse(references: first.references + second.references)
        }
    }

    /// The session throws the legacy GenerationError on macOS 27 (observed);
    /// the replacement LanguageModelError case is checked too for when the
    /// framework migrates.
    nonisolated private static func isContextOverflow(_ error: Error) -> Bool {
        if let error = error as? LanguageModelError, case .contextSizeExceeded = error {
            return true
        }
        if let error = error as? LanguageModelSession.GenerationError,
           case .exceededContextWindowSize = error {
            return true
        }
        return false
    }

    /// Splits at the paragraph (or line) break closest to the midpoint so a
    /// reference statement isn't cut mid-sentence more than necessary.
    nonisolated static func splitNearMidpoint(_ text: String) -> (String, String) {
        let target = text.count / 2

        for separator in ["\n\n", "\n"] {
            var best: (index: String.Index, distance: Int)?
            var searchStart = text.startIndex
            while let range = text.range(of: separator, range: searchStart..<text.endIndex) {
                let offset = text.distance(from: text.startIndex, to: range.lowerBound)
                let distance = abs(offset - target)
                if best == nil || distance < best!.distance {
                    best = (range.upperBound, distance)
                }
                searchStart = range.upperBound
            }
            // Only take a break point that lands in the middle half of the
            // text, so neither side ends up trivially small.
            if let best, best.distance <= text.count / 4 {
                return (String(text[..<best.index]), String(text[best.index...]))
            }
        }

        let midpoint = text.index(text.startIndex, offsetBy: target)
        return (String(text[..<midpoint]), String(text[midpoint...]))
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
