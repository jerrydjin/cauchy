// Appended to the existing test file only in the profiler's isolated archive.
// This opt-in diagnostic is not part of the ordinary test suite.
#if DEBUG
import Dispatch
extension LearningUIFixtureTests {
    func testProfileLearningReviewOverview() async throws {
        let profileRoot = FileManager.default.temporaryDirectory.appendingPathComponent("cauchy-ui-fixture-review-profile-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: profileRoot) }
        let pdf = try LearningUIFixture.makePDF()
        let seed = try LearningUIFixture.makeWorkspace(document: pdf, url: profileRoot.appendingPathComponent("authored.pdf"))
        let original = try XCTUnwrap(seed.learningStudyMap?.units.first)
        let prior = try XCTUnwrap(seed.learningSessions.first { $0.phase == .complete })
        let clock = Date(timeIntervalSince1970: 1_800_000_000)
        func identifier(_ value: Int) -> UUID {
            UUID(uuidString: String(format: "72000000-0000-4000-8000-%012d", value))!
        }
        var results: [[String: Any]] = []
        for (documentCount, unitCount, historyCount) in [(1, 12, 4), (12, 40, 6), (30, 80, 8)] {
            var units: [LearningStudyUnit] = []
            var sessions: [LearningSession] = []
            for index in 0..<unitCount {
                let unitID = identifier(1_000 + index)
                let targets = LearningStudyKind.allCases.enumerated().map { offset, kind in
                    LearningStudyTarget(id: identifier(10_000 + index * 3 + offset), unitID: unitID, kind: kind, objective: "Authored \(kind.rawValue) requirement \(index)")
                }
                units.append(.init(id: unitID, title: "Authored topic \(index)", anchorPage: original.anchorPage,
                    sourceQuote: original.sourceQuote, pageIndices: original.pageIndices, prerequisites: [],
                    proofRequired: true, proofQuote: original.proofQuote, gaps: [], targets: targets))
                for (targetIndex, target) in targets.enumerated() {
                    for history in 0..<historyCount {
                        var saved = prior
                        saved.id = identifier(100_000 + (index * 3 + targetIndex) * historyCount + history); saved.studyTarget = target
                        saved.reviewDueAt = clock.addingTimeInterval(-86_400)
                        var question = saved.attempts[0].question; question.kind = target.kind
                        var attempt = LearningAttempt(phase: .exitCheck, question: question,
                            answer: "Authored independent reasoning", assessment: saved.attempts[0].assessment,
                            assistanceUsed: false, providerID: "authored-profile", modelID: nil)
                        attempt.createdAt = clock.addingTimeInterval(Double(history - historyCount) * 86_400)
                        saved.attempts = [attempt]
                        sessions.append(saved)
                    }
                }
            }
            let map = LearningStudyMap(pageSignatures: seed.learningStudyMap!.pageSignatures, pages: [], units: units)
            let root = profileRoot.appendingPathComponent("case-\(documentCount)")
            let persistence = DocumentPersistenceService(root: root)
            let library = LearningLibraryStore(persistence: persistence)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            for index in 0..<documentCount {
                let id = identifier(200_000 + index)
                let url = profileRoot.appendingPathComponent("Authored-notes-\(index).pdf")
                let workspace = DocumentWorkspace(id: id, documentURL: url, learningSessions: sessions, learningStudyMap: map)
                _ = library.install(workspace, document: pdf, bookmarkData: nil)
                let directory = persistence.workspaceDirectory(for: id)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let summary = WorkspaceSummary(workspaceID: id, documentURL: url, lastOpenedAt: clock, highlightCount: 0, bookmarkData: nil)
                try encoder.encode(summary).write(to: persistence.summaryFileURL(for: id))
            }
            await library.refreshLibrary()
            let preparationStart = DispatchTime.now().uptimeNanoseconds
            await library.refreshReviewOverview()
            let preparationMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - preparationStart) / 1_000_000
            var samples: [Double] = []
            for _ in 0..<3 {
                let start = DispatchTime.now().uptimeNanoseconds
                let rows = library.reviewOverview(at: clock)
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                XCTAssertEqual(rows.count, documentCount)
                XCTAssertEqual(rows.reduce(0) { $0 + $1.dueCount }, documentCount * unitCount * 3)
                XCTAssertTrue(rows.allSatisfy { $0.inProgressCount == 0 })
            }
            results.append(["documents": documentCount, "unitsPerDocument": unitCount,
                "targetsPerDocument": unitCount * 3, "sessionsPerDocument": sessions.count,
                "preparationMilliseconds": preparationMilliseconds, "projectionMilliseconds": samples])
        }
        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("learning-review-profile.json")
        try JSONSerialization.data(withJSONObject: ["scope": "Authored live-library overview preparation and row projection; excludes PDF loading and closed-history decoding",
            "configuration": "Standard unoptimized Debug test host", "cases": results], options: [.prettyPrinted, .sortedKeys]).write(to: output)
    }
}
#endif
