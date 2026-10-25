// Opt-in disk/decode diagnostic, appended only to an isolated test archive.
#if DEBUG
import Dispatch
extension LearningUIFixtureTests {
    func testProfileClosedLearningReviewOverview() async throws {
        let profileRoot = FileManager.default.temporaryDirectory.appendingPathComponent("cauchy-ui-fixture-closed-profile-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: profileRoot) }
        let pdf = try LearningUIFixture.makePDF()
        let seed = try LearningUIFixture.makeWorkspace(document: pdf, url: profileRoot.appendingPathComponent("authored.pdf"))
        let prior = try XCTUnwrap(seed.learningSessions.first { $0.phase == .complete })
        let clock = Date(timeIntervalSince1970: 1_800_000_000)
        var results: [[String: Any]] = []
        for (documentCount, sessionCount) in [(1, 144), (8, 360), (16, 720)] {
            let root = profileRoot.appendingPathComponent("case-\(documentCount)")
            let persistence = DocumentPersistenceService(root: root)
            var learningBytes = 0, workspaceBytes = 0
            var originals: [UUID: Data] = [:]
            for index in 0..<documentCount {
                var workspace = seed
                workspace.id = UUID(uuidString: String(format: "73000000-0000-4000-8000-%012d", index))!
                workspace.documentURL = profileRoot.appendingPathComponent("Authored-closed-notes-\(index).pdf")
                workspace.learningSessions = (0..<sessionCount).map { history in
                    var saved = prior
                    saved.id = UUID(uuidString: String(format: "74000000-0000-4000-8000-%012d", history))!
                    saved.reviewDueAt = clock.addingTimeInterval(-86_400)
                    saved.attempts[0].createdAt = clock.addingTimeInterval(Double(history - sessionCount) * 3_600)
                    return saved
                }
                try await persistence.saveWorkspace(workspace, bookmarkData: nil)
                let file = persistence.workspaceDirectory(for: workspace.id).appendingPathComponent("learning.json")
                let data = try Data(contentsOf: file)
                originals[workspace.id] = data
                learningBytes += data.count
                workspaceBytes += try Data(contentsOf: persistence.workspaceFileURL(for: workspace.id)).count
            }
            let library = LearningLibraryStore(persistence: persistence)
            var refreshSamples: [Double] = [], rowSamples: [Double] = []
            for _ in 0..<2 {
                let start = DispatchTime.now().uptimeNanoseconds
                await library.refreshReviewOverview()
                refreshSamples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                let rowStart = DispatchTime.now().uptimeNanoseconds
                let rows = library.reviewOverview(at: clock)
                rowSamples.append(Double(DispatchTime.now().uptimeNanoseconds - rowStart) / 1_000_000)
                XCTAssertEqual(rows.count, documentCount)
                XCTAssertTrue(rows.allSatisfy { $0.dueCount == 1 && $0.inProgressCount == 0 })
                XCTAssertTrue(library.documents.isEmpty)
                XCTAssertNil(library.destination)
                XCTAssertEqual(library.unreadableReviewNotes, 0)
            }
            for (id, original) in originals {
                let file = persistence.workspaceDirectory(for: id).appendingPathComponent("learning.json")
                XCTAssertEqual(try Data(contentsOf: file), original)
            }
            results.append(["documents": documentCount, "sessionsPerDocument": sessionCount,
                "eligibleTargetsPerDocument": 1, "learningSidecarBytes": learningBytes, "workspaceBytes": workspaceBytes,
                "refreshMilliseconds": refreshSamples, "projectionMilliseconds": rowSamples])
        }
        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("learning-review-profile.json")
        try JSONSerialization.data(withJSONObject: ["scope": "Authored closed-history read, decode, schedule preparation and row projection; excludes PDF loading",
            "configuration": "Standard unoptimized Debug test host; first refresh is not an OS cold-cache measurement", "cases": results],
            options: [.prettyPrinted, .sortedKeys]).write(to: output)
    }
}
#endif
