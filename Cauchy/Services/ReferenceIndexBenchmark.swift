import Foundation
import FoundationModels
import PDFKit

/// Headless benchmark of on-device reference indexing, invoked with
/// `Cauchy --benchmark-indexing <pdf> [--pages N] [--output <dir>]`.
/// Runs the production per-page extraction path on evenly spaced sample pages,
/// compares against any existing (e.g. Gemini-built) cache for the same PDF,
/// writes report.md + report.json, and exits without normal UI interaction.
enum ReferenceIndexBenchmark {
    struct Config {
        let pdfURL: URL
        let sampleSize: Int
        let outputDirectory: URL?

        /// Returns nil when the arguments don't request benchmark mode.
        init?(arguments: [String]) {
            guard let flagIndex = arguments.firstIndex(of: "--benchmark-indexing"),
                  arguments.indices.contains(flagIndex + 1) else {
                return nil
            }
            pdfURL = URL(fileURLWithPath: (arguments[flagIndex + 1] as NSString).expandingTildeInPath)

            var pages = 12
            if let pagesIndex = arguments.firstIndex(of: "--pages"),
               arguments.indices.contains(pagesIndex + 1),
               let parsed = Int(arguments[pagesIndex + 1]), parsed > 0 {
                pages = parsed
            }
            sampleSize = pages

            if let outIndex = arguments.firstIndex(of: "--output"),
               arguments.indices.contains(outIndex + 1) {
                outputDirectory = URL(fileURLWithPath: (arguments[outIndex + 1] as NSString).expandingTildeInPath)
            } else {
                outputDirectory = nil
            }
        }
    }

    struct PageReport: Codable {
        let pageNumber: Int
        let pageTextCharacters: Int
        let succeeded: Bool
        let error: String?
        let parsedCount: Int
        let keptCount: Int
        let seconds: Double
        let references: [String]
        let cacheMatched: [String]
        let cacheMissed: [String]
        let cacheExtra: [String]
    }

    struct Summary: Codable {
        let pdfPath: String
        let pageCount: Int
        let sampledPages: Int
        let succeededPages: Int
        let failedPages: Int
        let emptyPages: Int
        let totalParsed: Int
        let totalKept: Int
        let latexKeepRate: Double
        let meanSecondsPerPage: Double
        let projectedFullBookMinutes: Double
        let cacheComparisonAvailable: Bool
        let cacheMatched: Int
        let cacheMissed: Int
        let cacheExtra: Int
        let recallVsCache: Double?
    }

    /// Deliberately nonisolated: the PDFDocument is created and consumed
    /// entirely off the main actor, matching LLMReferenceIndexBuilder.build.
    nonisolated static func run(config: Config) async -> Int32 {
        print("Cauchy reference-indexing benchmark (on-device model)")
        print("PDF: \(config.pdfURL.path)")

        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(let reason):
            print("ERROR: Apple Intelligence model unavailable: \(String(describing: reason))")
            return 1
        }

        guard let document = PDFDocument(url: config.pdfURL) else {
            print("ERROR: could not open PDF at \(config.pdfURL.path)")
            return 1
        }
        let pageCount = document.pageCount
        print("Pages: \(pageCount); sampling \(min(config.sampleSize, pageCount)) evenly spaced.")

        let cachedByPage = loadCacheEntriesByPage(for: config.pdfURL)
        if cachedByPage == nil {
            print("No existing reference-index cache found — running without comparison baseline.")
        } else {
            print("Found existing cache — comparing per page (note: the cache keeps one page per reference key, so per-page match counts are approximate).")
        }

        let sampleCount = min(config.sampleSize, pageCount)
        var sampled: [Int] = []
        for i in 0..<sampleCount {
            let index = Int((Double(i) + 0.5) * Double(pageCount) / Double(sampleCount))
            if !sampled.contains(index) { sampled.append(index) }
        }

        var reports: [PageReport] = []
        let model = SystemLanguageModel.default

        for pageIndex in sampled {
            let started = Date()
            do {
                let result = try await LLMReferenceIndexBuilder.indexSinglePage(
                    from: document,
                    pageIndex: pageIndex,
                    model: model
                )
                let seconds = Date().timeIntervalSince(started)
                let found = result.entries.keys.map(display).sorted()
                let cached = (cachedByPage?[pageIndex] ?? []).map(display).sorted()
                let matched = found.filter(cached.contains)
                let report = PageReport(
                    pageNumber: pageIndex + 1,
                    pageTextCharacters: result.pageTextCharacters,
                    succeeded: true,
                    error: nil,
                    parsedCount: result.parsedCount,
                    keptCount: result.entries.count,
                    seconds: seconds,
                    references: found,
                    cacheMatched: matched,
                    cacheMissed: cached.filter { !found.contains($0) },
                    cacheExtra: found.filter { !cached.contains($0) }
                )
                reports.append(report)
                print(String(format: "  p.%-4d %5.1fs  parsed %2d, kept %2d  %@",
                             pageIndex + 1, seconds, result.parsedCount, result.entries.count,
                             found.joined(separator: ", ")))
            } catch {
                let seconds = Date().timeIntervalSince(started)
                reports.append(PageReport(
                    pageNumber: pageIndex + 1,
                    pageTextCharacters: 0,
                    succeeded: false,
                    error: String(describing: error),
                    parsedCount: 0,
                    keptCount: 0,
                    seconds: seconds,
                    references: [],
                    cacheMatched: [],
                    cacheMissed: (cachedByPage?[pageIndex] ?? []).map(display).sorted(),
                    cacheExtra: []
                ))
                print("  p.\(pageIndex + 1)  FAILED after \(String(format: "%.1f", seconds))s: \(error)")
            }
        }

        let summary = makeSummary(
            config: config,
            pageCount: pageCount,
            reports: reports,
            hasCache: cachedByPage != nil
        )
        do {
            let directory = try writeReports(summary: summary, pages: reports, config: config)
            print("\nReport written to \(directory.path)")
        } catch {
            print("WARNING: could not write report files: \(error)")
        }
        printSummary(summary)
        return 0
    }

    /// `Cauchy --probe-retrieval <pdf> <query>`: builds the lexical index and
    /// prints the passages an ask would retrieve — a headless check of the
    /// retrieval pipeline.
    /// Prints exactly what ask-time retrieval would feed the assistant for the
    /// query: exact statements (with the route that surfaced each) and fused
    /// passages. Statements come from the on-disk reference cache only — the
    /// probe never spends model calls indexing.
    nonisolated static func runRetrievalProbe(pdfPath: String, query: String) async -> Int32 {
        let url = URL(fileURLWithPath: (pdfPath as NSString).expandingTildeInPath)
        guard let index = LexicalDocumentIndex.build(documentURL: url) else {
            print("ERROR: could not build lexical index for \(url.path)")
            return 1
        }

        var snapshot: DocumentReferenceIndexSnapshot?
        if let fingerprint = try? ReferenceIndexCacheStore.fingerprint(for: url),
           let cached = try? ReferenceIndexCacheStore.load(fingerprint: fingerprint) {
            let entries = cached.asSnapshot(pageCount: 0).entries
            snapshot = DocumentReferenceIndexSnapshot(
                entries: entries,
                pageCount: 0,
                bodyEmbeddings: DocumentReferenceIndexSnapshot.computeBodyEmbeddings(for: entries)
            )
        }

        let retrieval = await MainActor.run { () -> AskRetrieval in
            let referenceIndex = DocumentReferenceIndex()
            if let snapshot {
                referenceIndex.replace(with: snapshot)
            }
            return AskContextRetriever.retrieve(
                question: query,
                selectedText: "",
                surroundingText: "",
                pageIndex: nil,
                referenceIndex: referenceIndex,
                documentIndex: index,
                passageLimit: 5
            )
        }

        print("Query: \(query)")
        if snapshot == nil {
            print("(no reference-index cache for this PDF — statements unavailable; open it in Cauchy once to index it)")
        }
        print("\nExact statements (\(retrieval.statements.count)):")
        for (statement, route) in zip(retrieval.statements, retrieval.statementRoutes) {
            print("\n[\(route)] \(statement.prefix(500))")
        }
        print("\nFused passages (\(retrieval.passages.count)):")
        for (i, passage) in retrieval.passages.enumerated() {
            print("\n#\(i + 1) \(passage.prefix(400))")
        }
        return 0
    }

    // MARK: - Helpers

    private static func display(_ key: ReferenceKey) -> String {
        "\(key.kind.rawValue) \(key.number)"
    }

    private static func loadCacheEntriesByPage(for url: URL) -> [Int: [ReferenceKey]]? {
        guard let fingerprint = try? ReferenceIndexCacheStore.fingerprint(for: url),
              let cached = try? ReferenceIndexCacheStore.load(fingerprint: fingerprint) else {
            return nil
        }
        var byPage: [Int: [ReferenceKey]] = [:]
        for entry in cached.entries {
            guard let kind = ReferenceKind(rawValue: entry.kind) else { continue }
            byPage[entry.pageIndex, default: []].append(ReferenceKey(kind: kind, number: entry.number))
        }
        return byPage
    }

    private static func makeSummary(
        config: Config,
        pageCount: Int,
        reports: [PageReport],
        hasCache: Bool
    ) -> Summary {
        let succeeded = reports.filter(\.succeeded)
        let nonEmpty = succeeded.filter { $0.pageTextCharacters > 0 }
        let totalParsed = reports.reduce(0) { $0 + $1.parsedCount }
        let totalKept = reports.reduce(0) { $0 + $1.keptCount }
        let meanSeconds = nonEmpty.isEmpty ? 0 : nonEmpty.map(\.seconds).reduce(0, +) / Double(nonEmpty.count)
        let matched = reports.reduce(0) { $0 + $1.cacheMatched.count }
        let missed = reports.reduce(0) { $0 + $1.cacheMissed.count }
        let extra = reports.reduce(0) { $0 + $1.cacheExtra.count }

        return Summary(
            pdfPath: config.pdfURL.path,
            pageCount: pageCount,
            sampledPages: reports.count,
            succeededPages: succeeded.count,
            failedPages: reports.count - succeeded.count,
            emptyPages: succeeded.count - nonEmpty.count,
            totalParsed: totalParsed,
            totalKept: totalKept,
            latexKeepRate: totalParsed > 0 ? Double(totalKept) / Double(totalParsed) : 1,
            meanSecondsPerPage: meanSeconds,
            projectedFullBookMinutes: meanSeconds * Double(pageCount)
                / Double(LLMReferenceIndexBuilder.maxConcurrentPagesOnDevice) / 60,
            cacheComparisonAvailable: hasCache,
            cacheMatched: matched,
            cacheMissed: missed,
            cacheExtra: extra,
            recallVsCache: hasCache && (matched + missed) > 0
                ? Double(matched) / Double(matched + missed)
                : nil
        )
    }

    private static func printSummary(_ s: Summary) {
        print("""

        ── Summary ─────────────────────────────────────────
        Sampled pages:        \(s.sampledPages) of \(s.pageCount) (\(s.emptyPages) empty)
        Succeeded / failed:   \(s.succeededPages) / \(s.failedPages)
        References parsed:    \(s.totalParsed)
        Survived validation:  \(s.totalKept) (\(String(format: "%.0f%%", s.latexKeepRate * 100)))
        Mean time per page:   \(String(format: "%.1fs", s.meanSecondsPerPage))
        Projected full book:  \(String(format: "%.0f min", s.projectedFullBookMinutes)) (at concurrency \(LLMReferenceIndexBuilder.maxConcurrentPagesOnDevice))
        """)
        if s.cacheComparisonAvailable {
            let recall = s.recallVsCache.map { String(format: "%.0f%%", $0 * 100) } ?? "n/a"
            print("""
            Vs existing cache:    matched \(s.cacheMatched), missed \(s.cacheMissed), extra \(s.cacheExtra) (recall \(recall))
            """)
        }
    }

    private static func writeReports(summary: Summary, pages: [PageReport], config: Config) throws -> URL {
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let directory = config.outputDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Cauchy/benchmarks/\(timestamp)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        struct FullReport: Codable {
            let summary: Summary
            let pages: [PageReport]
        }
        try encoder.encode(FullReport(summary: summary, pages: pages))
            .write(to: directory.appendingPathComponent("report.json"), options: .atomic)

        var md = """
        # On-Device Reference Indexing Benchmark

        PDF: `\(summary.pdfPath)` (\(summary.pageCount) pages)

        | Page | Chars | Time | Parsed | Kept | References | Missed vs cache |
        |-----:|------:|-----:|-------:|-----:|------------|-----------------|

        """
        for page in pages {
            let refs = page.references.isEmpty ? "—" : page.references.joined(separator: ", ")
            let missed = page.cacheMissed.isEmpty ? "—" : page.cacheMissed.joined(separator: ", ")
            let status = page.succeeded ? String(format: "%.1fs", page.seconds) : "FAIL"
            md += "| \(page.pageNumber) | \(page.pageTextCharacters) | \(status) | \(page.parsedCount) | \(page.keptCount) | \(refs) | \(missed) |\n"
        }
        md += """

        - Succeeded/failed pages: \(summary.succeededPages)/\(summary.failedPages)
        - LaTeX keep rate: \(String(format: "%.0f%%", summary.latexKeepRate * 100))
        - Mean seconds/page: \(String(format: "%.1f", summary.meanSecondsPerPage)); projected full book: \(String(format: "%.0f min", summary.projectedFullBookMinutes))
        """
        if summary.cacheComparisonAvailable {
            let recall = summary.recallVsCache.map { String(format: "%.0f%%", $0 * 100) } ?? "n/a"
            md += "\n- Vs cache: matched \(summary.cacheMatched), missed \(summary.cacheMissed), extra \(summary.cacheExtra) (recall \(recall))\n"
        }
        for page in pages where page.error != nil {
            md += "\n**Page \(page.pageNumber) error:** \(page.error!)\n"
        }
        try md.data(using: .utf8)?
            .write(to: directory.appendingPathComponent("report.md"), options: .atomic)
        return directory
    }
}
