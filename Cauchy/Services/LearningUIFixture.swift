#if DEBUG
import AppKit
import CryptoKit
import Observation
import PDFKit
import SwiftUI

/// Development-only authored content. Neither the tutor nor source reviewer
/// can call a provider, and the store cannot import or synchronize real notes.
@MainActor
enum LearningUIFixture {
    static let workspaceID = UUID(uuidString: "70000000-0000-4000-8000-000000000001")!
    static let closedID = UUID(uuidString: "70000000-0000-4000-8000-000000000002")!
    static let imageID = UUID(uuidString: "70000000-0000-4000-8000-000000000003")!
    static let blockedID = UUID(uuidString: "70000000-0000-4000-8000-000000000004")!
    static let moduleID = UUID(uuidString: "70000000-0000-4000-8000-000000000005")!
    static let marker = "cauchy.learning-ui-fixture.v1\n"
    static let closedStatement = "A closed subset of a sequentially compact metric space is sequentially compact."
    static let imageStatement = "The continuous image of a sequentially compact metric space is sequentially compact."
    static let closedProof = "A sequence in a closed subset K is a sequence in X. Choose a convergent subsequence in X. Closedness puts its limit in K."
    static let imageProof = "Choose preimages for a sequence in f(X). A subsequence of preimages converges in X. Continuity sends that subsequence to a sequence converging to the image of its limit in f(X)."
    static let omission = "The proof is omitted from these authored fixture notes."
    static let sourcePages = ["""
    AUTHORED DEVELOPMENT FIXTURE - NOT LEARNER NOTES
    A metric space is sequentially compact if every sequence has a subsequence converging to a point of the space.
    \(closedStatement)
    Proof. \(closedProof)
    \(imageStatement)
    Proof. \(imageProof)
    A sequentially compact subset S of a metric space Y is closed and bounded in Y.
    Proof. If a lies in the closure of S, choose s_n in S with d(s_n,a)<1/n. Sequential compactness gives a subsequence converging in S; uniqueness of limits makes that limit a. For boundedness, an unbounded S permits s_n with d(s_n,s_0)>n. Such a sequence has no convergent subsequence, a contradiction.
    """, """
    AUTHORED DEVELOPMENT FIXTURE - SOURCE REVIEW SCENARIO
    A closed and bounded subset of a general metric space need not be compact.
    \(omission)
    This page intentionally has an unresolved candidate warning in the fixture inventory. The warning is not a verified extraction fault.
    Formula for visual comparison: the Euclidean norm of (x,y) is sqrt(x*x+y*y).
    """]

    static func requestedRoot(arguments: [String], bundleRoot: String?) -> String? {
        if let index = arguments.firstIndex(of: "--learning-ui-fixture") {
            return arguments.indices.contains(index + 1) ? arguments[index + 1] : ""
        }
        return bundleRoot
    }

    static func validatedRoot(_ path: String) throws -> URL {
        guard let root = LearningSourceReconciliationProbe.isolatedOutputURL(path),
              root.lastPathComponent.hasPrefix("cauchy-ui-fixture-"),
              root.lastPathComponent.count > "cauchy-ui-fixture-".count else {
            throw LearningStudyValidationError(reason: "Use a temporary directory named cauchy-ui-fixture-<name>. No normal library was opened.")
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw LearningError.invalidRange }
            let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
            if !files.isEmpty {
                guard (try? String(contentsOf: root.appendingPathComponent("fixture-format.txt"), encoding: .utf8)) == marker else {
                    throw LearningStudyValidationError(reason: "This nonempty directory is not a Cauchy UI fixture. Choose a fresh temporary directory.")
                }
            }
            if let entries = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
                for case let entry as URL in entries {
                    if try entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                        throw LearningStudyValidationError(reason: "Fixture storage cannot contain symbolic links to another library. Choose a fresh temporary directory.")
                    }
                }
            }
        }
        return root
    }

    static func makePDF() throws -> PDFDocument {
        let data = NSMutableData()
        var bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &bounds, nil) else { throw LearningError.noText }
        for text in sourcePages {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.black])
                .draw(in: CGRect(x: 36, y: 36, width: 540, height: 720))
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
        guard let document = PDFDocument(data: data as Data) else { throw LearningError.noText }
        return document
    }

    static func makeWorkspace(document: PDFDocument, url: URL, now: Date = Date()) throws -> DocumentWorkspace {
        let pages = try (0..<document.pageCount).map { index in
            guard let text = document.page(at: index)?.string else { throw LearningError.noText }
            return text
        }
        func unit(id: UUID, title: String, quote: String, proof: String?, page: Int, gaps: [String] = []) -> LearningStudyUnit {
            let kinds: [LearningStudyKind] = proof == nil ? [.concept] : [.concept, .proof, .application]
            let targets = kinds.enumerated().map { index, kind in
                let suffix = id == closedID ? 100 : id == imageID ? 200 : 300
                let targetID = UUID(uuidString: String(format: "70000000-0000-4000-8000-%012d", suffix + index))!
                return LearningStudyTarget(id: targetID, unitID: id, kind: kind, objective: "\(kind.label): justify and use \(title.lowercased()).")
            }
            return .init(id: id, title: title, anchorPage: page, sourceQuote: quote, pageIndices: [page],
                prerequisites: [], proofRequired: true, proofQuote: proof, gaps: gaps, targets: targets)
        }
        let closed = unit(id: closedID, title: "Closed subsets", quote: closedStatement, proof: closedProof, page: 0)
        let image = unit(id: imageID, title: "Continuous images", quote: imageStatement, proof: imageProof, page: 0)
        let blocked = unit(id: blockedID, title: "Unresolved source example", quote: "A closed and bounded subset of a general metric space need not be compact.",
            proof: nil, page: 1, gaps: ["Suspected extraction fault: compare the formula with the displayed original. This is an authored candidate warning.", "The proof is explicitly omitted."])
        let course = LearningCourse(title: "Authored Learn verification", overview: "Offline navigation and persistence fixture. No learner outcomes or mathematical model accuracy are measured.",
            modules: [.init(id: moduleID, title: "Connect the two source-supported ideas", goal: "Carry a subsequence limit through a continuous map.", unitIDs: [closedID, imageID]),
                      .init(title: "Blocked source chapter", goal: "Inspect source warnings without waiving a proof.", unitIDs: [closedID, blockedID])],
            connections: [.init(fromUnitID: closedID, toUnitID: imageID, reason: "Use closedness to keep the limit in the domain before applying continuity."),
                          .init(fromUnitID: closedID, toUnitID: blockedID, reason: "Compare a supported compactness consequence with a claim whose proof remains unavailable.")])
        let map = LearningStudyMap(pageSignatures: pages.map(LearningStudyInput.signature),
            pages: pages.indices.map { .init(pageIndex: $0, status: .mapped) }, units: [closed, image, blocked], course: course)
        let source = LearningSource(passages: [.init(pageIndex: 0, text: pages[0])])
        let target = closed.targets[0]
        var saved = LearningSession(source: source, lesson: lesson(source: source, target: target), providerID: "authored-offline-fixture", modelID: "deterministic-v1")
        saved.id = UUID(uuidString: "70000000-0000-4000-8000-000000000010")!
        saved.studyTarget = target
        saved.phase = .practice
        saved.answerDraft = "Saved fixture draft: closedness keeps the limit in K."
        saved.hintsRevealed = 1
        let reviewTarget = image.targets.first { $0.kind == .application }!
        var due = LearningSession(source: source, lesson: lesson(source: source, target: reviewTarget), phase: .complete,
            providerID: "authored-offline-fixture", modelID: "deterministic-v1",
            createdAt: now.addingTimeInterval(-2 * 86_400), updatedAt: now.addingTimeInterval(-2 * 86_400))
        due.id = UUID(uuidString: "70000000-0000-4000-8000-000000000011")!
        due.studyTarget = reviewTarget
        var attempt = LearningAttempt(phase: .exitCheck, question: due.lesson.exitCheck, answer: "Authored prior fixture answer, not learner outcome data.",
            assessment: .init(grade: .correct, feedback: "Authored fixture result for the due-review scenario.", nextStep: "Return for a delayed check.",
                criteria: due.lesson.exitCheck.gradingCriteria?.indices.map { .init(index: $0, outcome: .met, feedback: "Seeded fixture criterion.") }),
            assistanceUsed: false, providerID: "authored-offline-fixture", modelID: "deterministic-v1")
        attempt.createdAt = due.createdAt
        due.attempts = [attempt]
        due.reviewDueAt = now.addingTimeInterval(-86_400)
        return .init(id: workspaceID, documentURL: url, learningSessions: [saved, due], learningStudyMap: map)
    }

    static func lesson(source: LearningSource, target: LearningStudyTarget?) -> LearningLesson {
        let isImage = target?.unitID == imageID
        let statement = isImage ? imageStatement : closedStatement
        let proof = isImage ? imageProof : closedProof
        let kind = target?.kind ?? .concept
        let criteria = ["Use the sequential compactness hypothesis.", "Justify where the subsequence limit belongs.", "Conclude the required sequence property."]
        func question(_ prompt: String, hints: [String] = []) -> LearningQuestion {
            .init(prompt: prompt, expectedAnswer: proof, hints: hints, kind: kind, gradingCriteria: criteria)
        }
        return .init(title: "Fixture lesson: \(isImage ? "continuous images" : "closed subsets")", objective: target?.objective ?? statement,
            sourceQuote: statement, explanation: proof, workedExample: "A closed interval in the real line illustrates keeping a subsequence limit inside the subset.",
            diagnostic: question("Where must a subsequence limit lie in this argument? Explain the relevant hypothesis."),
            practice: question("Explain the argument in the source, including the role of \(isImage ? "continuity" : "closedness").", hints: ["Track the limit before concluding."]),
            exitCheck: question("Prove this consequence for a different named subset or map, with all hypotheses stated: \(statement)"),
            proof: kind == .proof ? .init(statement: statement, assumptions: ["The metric-space hypotheses in the statement hold."],
                strategy: "Start with an arbitrary sequence and track a convergent subsequence.",
                steps: [.init(claim: proof, justification: "Apply the source sequence argument and its stated hypotheses.")],
                conclusion: statement, sourceQuote: proof) : nil)
    }

    static func challenge(request: LearningChapterRequest, fresh: Bool = false) -> LearningChapterChallenge {
        let assumptions = "Let X be sequentially compact, K a closed subset of X, and f: X -> Y continuous between metric spaces."
        let criteria = ["Choose a sequence and justified preimages or domain restriction.", "Use closedness to keep the domain subsequence limit in K.", "Apply continuity and conclude the requested image property."]
        return .init(moduleID: request.moduleID, title: "Fixture: carry a limit through a map", connection: request.connection,
            ideas: request.units.map { .init(unitID: $0.id, title: $0.title, pageIndex: 0, sourceQuote: $0.sourceQuote) },
            assumptions: [assumptions], question: .init(prompt: assumptions + (fresh ? " Prove that f(K) is closed and bounded in Y." : " Prove that f(K) is sequentially compact."),
                expectedAnswer: "A sequence in f(K) has preimages in K. Sequential compactness of X yields a subsequence converging in X; closedness puts the limit in K. Continuity gives convergence in f(K). For the fresh consequence, apply the supplied closedness and boundedness argument.",
                hints: [], kind: .proof, gradingCriteria: criteria),
            criteria: [.init(index: 0, unitIDs: [imageID]), .init(index: 1, unitIDs: [closedID]), .init(index: 2, unitIDs: [imageID])],
            refresher: .init(unitID: closedID, pageIndex: 0, sourceQuote: closedStatement,
                explanation: "The subsequence initially converges in X. Closedness of K puts that same limit in K, so its image is in f(K).",
                check: .init(prompt: "Why does the limit in X of a convergent sequence in the closed subset K lie in K?",
                    expectedAnswer: "Closed subsets contain the limits in X of their convergent sequences.", hints: [], kind: .concept)))
    }
}

@MainActor
private final class LearningUIFixtureTutor: LearningTutorProtocol {
    let providerID = "authored-offline-fixture"
    let modelID: String? = "deterministic-v1"
    func makeLesson(source: LearningSource) async throws -> LearningLesson { LearningUIFixture.lesson(source: source, target: nil) }
    func makeLesson(source: LearningSource, target: LearningStudyTarget) async throws -> LearningLesson { LearningUIFixture.lesson(source: source, target: target) }
    func makeChapterChallenge(request: LearningChapterRequest, source: LearningSource, previous: [String]) async throws -> LearningChapterChallenge {
        LearningUIFixture.challenge(request: request, fresh: !previous.isEmpty)
    }
    func assess(question: LearningQuestion, answer: String, source: LearningSource) async throws -> LearningAssessment {
        let token = answer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let outcome: LearningCriterionAssessment.Outcome = token == "fixture correct" ? .met : token == "fixture uncertain" ? .uncertain : .notMet
        return .init(grade: outcome == .met ? .correct : outcome == .uncertain ? .uncertain : .partial,
            feedback: "Deterministic fixture response; this does not assess mathematical correctness.",
            nextStep: "Use 'fixture correct', 'fixture uncertain', or any other text to exercise result handling.",
            criteria: question.gradingCriteria?.indices.map { .init(index: $0, outcome: outcome, feedback: "Offline fixture outcome for this criterion.") })
    }
    func newExitQuestion(lesson: LearningLesson, source: LearningSource, previous: [String]) async throws -> LearningQuestion {
        .init(prompt: "Authored fixture follow-up \(previous.count + 1): explain which hypothesis keeps this source argument valid.",
            expectedAnswer: lesson.exitCheck.expectedAnswer, hints: [], kind: lesson.exitCheck.kind, gradingCriteria: lesson.exitCheck.gradingCriteria)
    }
}

@MainActor
private final class LearningUIFixturePlanner: LearningStudyPlannerProtocol {
    let providerID = "authored-offline-fixture"
    let modelID: String? = "deterministic-v1"
    let sourceLimit = 38_000
    func plan(source: LearningSource, corePages: [Int]) async throws -> LearningStudyPlanResponse {
        throw LearningStudyValidationError(reason: "This offline fixture has a fixed authored inventory. Use a fresh fixture directory to reset it.")
    }
    func course(units: [LearningStudyUnit]) async throws -> LearningCourse { throw LearningError.invalidCourse }
}

@MainActor
private final class LearningUIFixtureReconciler: LearningSourceReconcilerProtocol {
    let providerID = "authored-offline-fixture"
    let modelID: String? = "deterministic-v1"
    let sourceLimit = 38_000
    func review(unit: LearningStudyUnit, source: LearningSource, pageCount: Int) async throws -> LearningReconciliationResponse {
        let passage = source.passages.first { $0.pageIndex == unit.anchorPage }
        return .init(issues: unit.gaps.enumerated().map { index, gap in
            let extraction = LearningSourceReconciler.extractionConcern(gap)
            let corrected = passage?.correction != nil
            return .init(gapIndex: index, disposition: extraction ? (corrected ? .foundElsewhere : .extractionProblem) : .omitted,
                explanation: extraction ? (corrected ? "The labelled user transcription is available for this fixture review." : "Compare the candidate warning with the original page; this offline response does not verify a fault.") : "The authored source explicitly omits the proof; the obligation stays open.",
                evidence: passage.map { [.init(pageIndex: $0.pageIndex, quote: extraction ? $0.text : LearningUIFixture.omission)] } ?? [])
        }, requestedPages: [], proofObjective: nil, proofEvidence: [])
    }
}

@MainActor
@Observable
final class LearningUIFixtureController {
    let rootPath: String
    let preferences: UserDefaults
    private(set) var library: LearningLibraryStore?
    private(set) var error: String?
    private(set) var isLoading = false

    init(rootPath: String) {
        self.rootPath = rootPath
        let key = SHA256.hash(data: Data(rootPath.utf8)).map { String(format: "%02x", $0) }.joined()
        preferences = UserDefaults(suiteName: "com.cauchy.learning-ui-fixture.\(key)")!
    }

    func load() async {
        guard library == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let root = try LearningUIFixture.validatedRoot(rootPath)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try LearningUIFixture.marker.write(to: root.appendingPathComponent("fixture-format.txt"), atomically: true, encoding: .utf8)
            let url = root.appendingPathComponent("Authored-Learn-Fixture.pdf")
            let document: PDFDocument
            if FileManager.default.fileExists(atPath: url.path) {
                guard let loaded = PDFDocument(url: url) else { throw LearningError.noText }
                document = loaded
            } else {
                document = try LearningUIFixture.makePDF()
                guard document.write(to: url) else { throw LearningError.noText }
            }
            let persistence = DocumentPersistenceService(root: root.appendingPathComponent("workspaces"))
            let saved = await persistence.loadWorkspace(id: LearningUIFixture.workspaceID)
            let workspace = try saved?.workspace ?? LearningUIFixture.makeWorkspace(document: document, url: url)
            guard workspace.documentURL.standardizedFileURL.resolvingSymlinksInPath() == url.standardizedFileURL.resolvingSymlinksInPath() else {
                throw LearningStudyValidationError(reason: "The fixture record points outside its authored PDF. Choose a fresh fixture directory.")
            }
            if saved == nil { try await persistence.saveWorkspace(workspace, bookmarkData: nil) }
            let store = LearningLibraryStore(verificationPersistence: persistence) { workspace, pdf, bookmark in
                LearningDocument(workspace: workspace, document: pdf, bookmarkData: nil,
                    learning: LearningViewModel(makeTutor: { LearningUIFixtureTutor() }),
                    studyMap: LearningStudyMapViewModel(map: workspace.learningStudyMap, reconciler: LearningUIFixtureReconciler(),
                                                       makePlanner: { LearningUIFixturePlanner() }), isVerificationFixture: true)
            }
            _ = store.install(workspace, document: document, bookmarkData: nil)
            store.destination = .studyMap(workspace.id)
            await store.refreshLibrary()
            library = store
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func flush() async throws { try await library?.flushPendingSaves() }
}

struct LearningUIFixtureView: View {
    @Bindable var controller: LearningUIFixtureController
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Authored development fixture · offline tutor · isolated temporary library", systemImage: "testtube.2")
                    .font(.headline)
                Text("Assessment controls: enter ‘fixture correct’ or ‘fixture uncertain’; other answers produce partial feedback. These responses do not grade mathematics.")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            Divider()
            if let library = controller.library {
                LearningWorkspaceView(library: library).defaultAppStorage(controller.preferences)
            } else if let error = controller.error {
                ContentUnavailableView("Fixture could not open", systemImage: "exclamationmark.triangle", description: Text(error))
            } else { ProgressView("Preparing authored fixture…").frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .frame(minWidth: 1000, minHeight: 760)
        .task { await controller.load() }
    }
}
#endif
