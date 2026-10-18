import Foundation
import XCTest
@testable import Cauchy

/// Classifies CLI outcomes without launching anything. A successful answer that
/// happens to mention signing in must stay an answer.
final class AssistantFailureClassificationTests: XCTestCase {
    func testSignedOutAndUnknownModelAreRecoverable() {
        let signedOut = AssistantFailure.classify(
            connectorID: .codex,
            modelID: "gpt-6.1-sol",
            parserError: nil,
            parserText: nil,
            rawOutput: "",
            processError: .processFailed(exitCode: 2, stderr: "not logged in")
        )
        XCTAssertEqual(signedOut, .notSignedIn(.codex))

        let unknown = AssistantFailure.classify(
            connectorID: .codex,
            modelID: "gpt-6-sol",
            parserError: "The model gpt-6-sol is not supported with this account.",
            parserText: nil,
            rawOutput: "",
            processError: .processFailed(exitCode: 4, stderr: "")
        )
        XCTAssertEqual(unknown, .modelUnavailable(.codex, modelName: "gpt-6-sol"))
    }

    func testEmptyGarbageTimeoutAndAuthWordsInsideAnAnswer() {
        XCTAssertEqual(
            AssistantFailure.classify(
                connectorID: .codex, modelID: "gpt-6.1-sol",
                parserError: nil, parserText: nil, rawOutput: "", processError: nil
            ),
            .emptyOutput(.codex)
        )
        XCTAssertEqual(
            AssistantFailure.classify(
                connectorID: .codex, modelID: "gpt-6.1-sol",
                parserError: nil, parserText: nil, rawOutput: "not-json", processError: nil
            ),
            .unreadableOutput(.codex)
        )
        XCTAssertEqual(
            AssistantFailure.classify(
                connectorID: .claudeCode, modelID: "sonnet",
                parserError: nil, parserText: nil, rawOutput: "", processError: .timedOut
            ),
            .timedOut(.claudeCode)
        )
        XCTAssertNil(
            AssistantFailure.classify(
                connectorID: .codex, modelID: "gpt-6.1-sol",
                parserError: nil,
                parserText: "You can sign in to ChatGPT from the vendor's own app.",
                rawOutput: "You can sign in to ChatGPT from the vendor's own app.",
                processError: nil
            )
        )
    }

    func testAntigravityEmptyOutputKeepsTheQuotaSentence() {
        let failure = AssistantFailure.classify(
            connectorID: .antigravity, modelID: nil,
            parserError: nil, parserText: nil, rawOutput: "   ", processError: nil
        )
        guard case .failed(let id, let message) = failure else {
            return XCTFail("Expected a readable Antigravity failure, got \(String(describing: failure))")
        }
        XCTAssertEqual(id, .antigravity)
        XCTAssertTrue(message.contains("quota"))
    }

    func testAskBoxStaysClosedUntilReadyAndNamesTheNextStep() {
        let signedOut = AssistantFailure.notSignedIn(.codex).askPresentation()
        XCTAssertFalse(signedOut.canAsk)
        XCTAssertEqual(signedOut.buttonTitle, "Sign in to ChatGPT to start asking")
        XCTAssertEqual(signedOut.recovery, .setup(.codex))

        let missing = AssistantFailure.notInstalled(.claudeCode).askPresentation()
        XCTAssertEqual(missing.buttonTitle, "Install Claude Code to start asking")

        let model = AssistantFailure.modelUnavailable(.codex, modelName: "GPT-6 Sol").askPresentation()
        XCTAssertFalse(model.canAsk)
        XCTAssertNil(model.buttonTitle)
        XCTAssertNil(model.recovery)

        let key = AssistantFailure.invalidAPIKey(.openai).askPresentation()
        XCTAssertEqual(key.buttonTitle, "Update your OpenAI API key to start asking")
        XCTAssertEqual(key.recovery, .settings)

        let ready = AskPresentation.make(connector: AssistantConnectorID.codex.connector, state: .ready)
        XCTAssertTrue(ready.canAsk)
        XCTAssertNil(ready.buttonTitle)
        XCTAssertNotEqual(
            AskPresentation.make(connector: AssistantConnectorID.codex.connector, state: .unknown).probeToken,
            ready.probeToken
        )
        XCTAssertEqual(
            AskPresentation.make(connector: AssistantConnectorID.codex.connector, state: .unknown).probeToken,
            AskPresentation.make(connector: AssistantConnectorID.codex.connector, state: .checking).probeToken
        )
    }

    func testCodexErrorObjectAndAppServerEventsAreReadable() {
        var parser = CodexStreamParser()
        _ = parser.consume(line: #"{"type":"error","status":400,"error":{"message":"The model gpt-6-sol is not supported"}}"#)
        XCTAssertEqual(parser.errorMessage, "The model gpt-6-sol is not supported")
        XCTAssertNil(parser.finalText)

        var stream = CodexStreamParser()
        XCTAssertEqual(
            stream.consume(line: #"{"method":"item/agentMessage/delta","params":{"delta":"Hello"}}"#),
            "Hello"
        )
        _ = stream.consume(line: #"{"method":"turn/failed","params":{"error":{"message":"Not logged in"}}}"#)
        XCTAssertEqual(stream.errorMessage, "Not logged in")

        let failure = AssistantFailure.classify(
            connectorID: .codex,
            modelID: "gpt-6.1-sol",
            parserError: parser.errorMessage,
            parserText: parser.finalText,
            rawOutput: "",
            processError: nil
        )
        XCTAssertEqual(failure, .modelUnavailable(.codex, modelName: "GPT-6.1 Sol"))
    }

    func testRequestsNameTheModelTheReaderPicked() {
        let args = CLIInvocation.codexArguments(prompt: "Reply with exactly OK.", modelID: "gpt-6-sol")
        XCTAssertEqual(Array(args.suffix(2)), ["--model", "gpt-6-sol"])
        XCTAssertTrue(args.contains("--json"))
        XCTAssertTrue(args.contains("read-only"))
        let claude = CLIInvocation.claudeArguments(prompt: "Hi", instructions: "Be brief", modelID: "opus")
        XCTAssertEqual(Array(claude.suffix(2)), ["--model", "opus"])
    }
}

/// Ready is cached only after a probe succeeds, and a missing binary or key
/// never counts. These tests never launch a CLI or touch the shared store.
@MainActor
final class ProviderReadinessStoreTests: XCTestCase {
    func testMissingBinaryOrKeyDoesNotProbeAndDoesNotLookReady() async throws {
        let probe = ScriptedProbe()
        let installed = Flag(false)
        let store = try makeStore(probe: probe, installed: installed, hasKey: Flag(true))

        let missing = store.state(for: .codex, modelID: "gpt-6.1-sol")
        XCTAssertEqual(missing, .blocked(.notInstalled(.codex)))
        await store.probeIfNeeded(connectorID: .codex, modelID: "gpt-6.1-sol")
        XCTAssertEqual(probe.callCount, 0)
        let ask = AskPresentation.make(connector: AssistantConnectorID.codex.connector, state: missing)
        XCTAssertFalse(ask.canAsk)
        XCTAssertEqual(ask.buttonTitle, "Install Codex to start asking")

        let keys = Flag(false)
        let api = try makeStore(probe: ScriptedProbe(), installed: Flag(true), hasKey: keys)
        XCTAssertEqual(
            api.state(for: .openaiAPI, modelID: "gpt-6.1-sol"),
            .blocked(.missingAPIKey(.openai))
        )
        await api.probeIfNeeded(connectorID: .openaiAPI, modelID: "gpt-6.1-sol")
        XCTAssertNotEqual(api.state(for: .openaiAPI, modelID: "gpt-6.1-sol"), .ready)
    }

    func testReadyIsCachedOnlyAfterSuccessAndRerunAfterFailure() async throws {
        let probe = ScriptedProbe()
        let store = try makeStore(probe: probe, installed: Flag(true), hasKey: Flag(true))
        let model = "gpt-6.1-sol"
        XCTAssertEqual(store.state(for: .codex, modelID: model), .unknown)
        XCTAssertFalse(AskPresentation.make(connector: AssistantConnectorID.codex.connector, state: .unknown).canAsk)

        probe.result = .notSignedIn(.codex)
        let denied = await store.probe(connectorID: .codex, modelID: model, force: true)
        XCTAssertEqual(denied, .notSignedIn(.codex))
        XCTAssertEqual(store.state(for: .codex, modelID: model), .blocked(.notSignedIn(.codex)))
        await store.probeIfNeeded(connectorID: .codex, modelID: model)
        XCTAssertEqual(probe.callCount, 1)

        probe.result = nil
        let ok = await store.probe(connectorID: .codex, modelID: model, force: true)
        XCTAssertNil(ok)
        XCTAssertEqual(store.state(for: .codex, modelID: model), .ready)
        let calls = probe.callCount
        _ = await store.probe(connectorID: .codex, modelID: model, force: false)
        await store.probeIfNeeded(connectorID: .codex, modelID: model)
        XCTAssertEqual(probe.callCount, calls)

        store.record(.timedOut(.codex), connectorID: .codex, modelID: model)
        XCTAssertEqual(store.state(for: .codex, modelID: model), .blocked(.timedOut(.codex)))
        store.record(.cancelled, connectorID: .codex, modelID: model)
        XCTAssertEqual(store.state(for: .codex, modelID: model), .blocked(.timedOut(.codex)))

        _ = await store.probe(connectorID: .codex, modelID: model, force: true)
        XCTAssertEqual(store.state(for: .codex, modelID: model), .ready)
        store.record(.cancelled, connectorID: .codex, modelID: model)
        XCTAssertEqual(store.state(for: .codex, modelID: model), .ready)
    }

    func testSuccessSurvivesANewStoreUntilTheBinaryDisappears() async throws {
        let probe = ScriptedProbe()
        let installed = Flag(true)
        let defaults = try makeDefaults()
        let store = try makeStore(defaults: defaults, probe: probe, installed: installed, hasKey: Flag(true))
        let model = "gpt-6.1-sol"
        probe.result = nil
        _ = await store.probe(connectorID: .codex, modelID: model, force: true)

        let restored = try makeStore(defaults: defaults, probe: ScriptedProbe(), installed: Flag(true), hasKey: Flag(true))
        XCTAssertEqual(restored.state(for: .codex, modelID: model), .ready)

        installed.value = false
        XCTAssertEqual(store.state(for: .codex, modelID: model), .blocked(.notInstalled(.codex)))
        installed.value = true
        XCTAssertEqual(store.state(for: .codex, modelID: model), .unknown)
        probe.result = .notSignedIn(.codex)
        await store.probeIfNeeded(connectorID: .codex, modelID: model)
        XCTAssertEqual(store.state(for: .codex, modelID: model), .blocked(.notSignedIn(.codex)))
    }

    func testExplicitConnectorDoesNotFallThroughWhenTheKeyIsMissing() {
        guard !KeychainService.hasKey(for: .openai) else { return }
        let previous = UserDefaults.standard.string(forKey: AssistantPreferences.selectionKey)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: AssistantPreferences.selectionKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AssistantPreferences.selectionKey)
            }
        }
        UserDefaults.standard.set(AssistantConnectorID.openaiAPI.rawValue, forKey: AssistantPreferences.selectionKey)
        let assistant = ReadingAssistantFactory.makeAssistant()
        XCTAssertEqual(assistant.provider, .openaiAPI)
        XCTAssertNotEqual(assistant.provider, .onDevice)
        XCTAssertEqual(assistant.availability, .apiKeyMissing(.openai))
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "cauchy.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeStore(
        defaults: UserDefaults? = nil,
        probe: ScriptedProbe,
        installed: Flag,
        hasKey: Flag
    ) throws -> ProviderReadinessStore {
        ProviderReadinessStore(
            defaults: defaults ?? (try makeDefaults()),
            prober: probe,
            binaryIsInstalled: { @MainActor _ in installed.value },
            apiKeyIsStored: { @MainActor _ in hasKey.value }
        )
    }
}

/// The states that used to kill the process: the child exits immediately, writes
/// stderr, or never exits. The binary is a script, never a real vendor CLI.
@MainActor
final class CLIProviderScriptTests: XCTestCase {
    func testSignedOutCodexFailsInTheAnswerInsteadOfCrashing() async throws {
        let failure = try await requireFailure(
            .codex,
            modelID: "gpt-6.1-sol",
            script: """
            #!/bin/sh
            printf '%s\\n' '{"type":"error","error":{"message":"Not logged in. Run codex login"}}'
            printf '%s\\n' 'error: not logged in' >&2
            exit 2
            """
        )
        XCTAssertEqual(failure, .notSignedIn(.codex))
        XCTAssertEqual(failure.statusLine, "Codex is not signed in.")
    }

    func testRejectedModelFailsInTheAnswerInsteadOfCrashing() async throws {
        let failure = try await requireFailure(
            .codex,
            modelID: "gpt-6.1-sol",
            script: """
            #!/bin/sh
            printf '%s\\n' '{"type":"error","status":400,"error":{"message":"The model gpt-6.1-sol is not supported with this account."}}'
            exit 0
            """
        )
        XCTAssertEqual(failure, .modelUnavailable(.codex, modelName: "GPT-6.1 Sol"))
    }

    func testEmptyGarbageAndStderrAreMessages() async throws {
        let empty = try await requireFailure(.codex, modelID: "gpt-6.1-sol", script: "#!/bin/sh\nexit 0\n")
        XCTAssertEqual(empty, .emptyOutput(.codex))

        let garbage = try await requireFailure(
            .codex, modelID: "gpt-6.1-sol",
            script: "#!/bin/sh\nprintf '%s\\n' 'this is not json'\nexit 0\n"
        )
        XCTAssertEqual(garbage, .unreadableOutput(.codex))

        let stderr = try await requireFailure(
            .codex, modelID: "gpt-6.1-sol",
            script: "#!/bin/sh\nprintf '%s\\n' 'fixture failure' >&2\nexit 7\n"
        )
        XCTAssertEqual(stderr, .failed(.codex, "fixture failure"))
    }

    func testSuccessfulCodexAnswerIsReturned() async throws {
        let binary = try writeScript("""
        #!/bin/sh
        printf '%s\\n' '{"type":"item.completed","item":{"type":"agent_message","text":"The answer is 4."}}'
        exit 0
        """)
        let service = CLIAgentAssistantService(connector: .codex, modelID: "gpt-6.1-sol", binaryURL: binary)
        let answer = try await service.ask(question: "What is 2 + 2?", retrieval: .empty)
        XCTAssertEqual(answer, "The answer is 4.")
        XCTAssertFalse(service.isResponding)
    }

    func testClaudeAuthenticationFailureAndAntigravitySilence() async throws {
        let claude = try await requireFailure(
            .claudeCode, modelID: "sonnet",
            script: """
            #!/bin/sh
            printf '%s\\n' '{"type":"result","is_error":true,"result":"authentication_failed"}'
            exit 1
            """
        )
        XCTAssertEqual(claude, .notSignedIn(.claudeCode))

        let agy = try await requireFailure(.antigravity, modelID: nil, script: "#!/bin/sh\nexit 0\n")
        guard case .failed(let id, let message) = agy else {
            return XCTFail("Expected Antigravity's empty-output failure")
        }
        XCTAssertEqual(id, .antigravity)
        XCTAssertTrue(message.contains("sign-in"))
    }

    func testTimeoutAndCancelStayInsideTheAnswer() async throws {
        let timeout = try await requireFailure(
            .codex, modelID: "gpt-6.1-sol",
            script: "#!/bin/sh\nsleep 30\nexit 0\n",
            timeout: 0.4
        )
        XCTAssertEqual(timeout, .timedOut(.codex))

        let binary = try writeScript("#!/bin/sh\nsleep 30\nexit 0\n")
        let service = CLIAgentAssistantService(connector: .codex, modelID: "gpt-6.1-sol", binaryURL: binary)
        service.requestTimeout = 30
        let task = Task { try await service.ask(question: "What is 2 + 2?", retrieval: .empty) }
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("A cancelled ask must not succeed")
        } catch AssistantFailure.cancelled {
        } catch is CancellationError {
        } catch {
            XCTFail("Cancellation crashed or escaped: \(error)")
        }
        XCTAssertFalse(service.isResponding)
    }

    func testMissingExecutableIsALaunchFailure() async throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("cauchy-missing-\(UUID().uuidString)")
        let service = CLIAgentAssistantService(connector: .codex, modelID: "gpt-6.1-sol", binaryURL: missing)
        do {
            _ = try await service.ask(question: "Hello", retrieval: .empty)
            XCTFail("A missing binary must fail")
        } catch let failure as AssistantFailure {
            guard case .failed(let id, let message) = failure else {
                return XCTFail("Expected a launch failure, got \(failure)")
            }
            XCTAssertEqual(id, .codex)
            XCTAssertTrue(message.contains("Could not launch"))
        }
    }

    private func requireFailure(
        _ connector: AssistantConnectorID,
        modelID: String?,
        script: String,
        timeout: TimeInterval = 5
    ) async throws -> AssistantFailure {
        let binary = try writeScript(script)
        let service = CLIAgentAssistantService(connector: connector, modelID: modelID, binaryURL: binary)
        service.requestTimeout = timeout
        do {
            let text = try await service.ask(question: "What is 2 + 2?", retrieval: .empty)
            XCTFail("Expected a failure, got \(text)")
            throw AssistantFailure.failed(connector, "expected a failure")
        } catch let failure as AssistantFailure {
            XCTAssertFalse(service.isResponding)
            return failure
        }
    }

    private func writeScript(_ body: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cauchy-fake-cli-\(UUID().uuidString)")
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o755)],
            ofItemAtPath: url.path
        )
        return url
    }
}

/// BYOK failures stay typed. The session is ephemeral and never leaves the test.
final class CloudProviderFailureTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CloudHTTPStub.self]
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        session.invalidateAndCancel()
        session = nil
        super.tearDown()
    }

    func testInvalidKeyUnknownModelAndGarbageDoNotCrash() async {
        CloudHTTPStub.install(status: 401, body: Data(#"{"error":{"message":"Incorrect API key"}}"#.utf8))
        let invalid = await CloudReadinessProbe.run(
            provider: .openai, apiKey: "sk-test", modelID: "gpt-6.1-sol", session: session
        )
        XCTAssertEqual(invalid, .invalidAPIKey(.openai))

        CloudHTTPStub.install(
            status: 400,
            body: Data(#"{"error":{"message":"The model gpt-6-sol is not supported"}}"#.utf8)
        )
        let model = await CloudReadinessProbe.run(
            provider: .openai, apiKey: "sk-test", modelID: "gpt-6-sol", session: session
        )
        XCTAssertEqual(model, .modelUnavailable(.openaiAPI, modelName: "gpt-6-sol"))

        CloudHTTPStub.install(status: 404, body: Data(#"{"error":{"message":"not found"}}"#.utf8))
        let missing = await CloudReadinessProbe.run(
            provider: .openai, apiKey: "sk-test", modelID: "gpt-6.1-sol", session: session
        )
        XCTAssertEqual(missing, .modelUnavailable(.openaiAPI, modelName: "GPT-6.1 Sol"))

        CloudHTTPStub.install(status: 200, body: Data("this is not an event stream\n".utf8))
        let garbage = await CloudReadinessProbe.run(
            provider: .openai, apiKey: "sk-test", modelID: "gpt-6.1-sol", session: session
        )
        XCTAssertEqual(garbage, .emptyOutput(.openaiAPI))

        CloudHTTPStub.install(status: 500, body: Data())
        let server = await CloudReadinessProbe.run(
            provider: .openai, apiKey: "sk-test", modelID: "gpt-6.1-sol", session: session
        )
        XCTAssertEqual(server, .failed(.openaiAPI, ""))

        CloudHTTPStub.install(status: 500, body: Data(), failWhileReadingBody: true)
        let dropped = await CloudReadinessProbe.run(
            provider: .openai, apiKey: "sk-test", modelID: "gpt-6.1-sol", session: session
        )
        guard case .failed(let droppedID, _) = dropped else {
            return XCTFail("A body that disappears must still be a chat failure, got \(String(describing: dropped))")
        }
        XCTAssertEqual(droppedID, .openaiAPI)

        CloudHTTPStub.install(status: 500, body: Data(repeating: 0x78, count: 20_000))
        let huge = await CloudReadinessProbe.run(
            provider: .openai, apiKey: "sk-test", modelID: "gpt-6.1-sol", session: session
        )
        guard case .failed(let id, let message) = huge else {
            return XCTFail("Expected a capped server failure, got \(String(describing: huge))")
        }
        XCTAssertEqual(id, .openaiAPI)
        XCTAssertLessThanOrEqual(message.count, 8_000)

        let ok = Data("data: {\"choices\":[{\"delta\":{\"content\":\"OK\"}}]}\n\n".utf8)
        CloudHTTPStub.install(status: 200, body: ok)
        let success = await CloudReadinessProbe.run(
            provider: .openai, apiKey: "sk-test", modelID: "gpt-6.1-sol", session: session
        )
        XCTAssertNil(success)
    }
}

private final class Flag: @unchecked Sendable {
    var value: Bool
    init(_ value: Bool) { self.value = value }
}

private final class ScriptedProbe: ProviderProbing, @unchecked Sendable {
    private let lock = NSLock()
    var result: AssistantFailure?
    private var calls = 0

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func probe(connectorID: AssistantConnectorID, modelID: String?) async -> AssistantFailure? {
        lock.lock()
        calls += 1
        let result = result
        lock.unlock()
        return result
    }
}

private final class CloudHTTPStub: URLProtocol, @unchecked Sendable {
    private final class Box: @unchecked Sendable {
        let lock = NSLock()
        var status = 200
        var body = Data()
        var failWhileReadingBody = false
    }

    private static let box = Box()

    static func install(status: Int, body: Data, failWhileReadingBody: Bool = false) {
        box.lock.lock()
        box.status = status
        box.body = body
        box.failWhileReadingBody = failWhileReadingBody
        box.lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.openai.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        box.lock.lock()
        let status = box.status
        let body = box.body
        let fail = box.failWhileReadingBody
        box.lock.unlock()

        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if fail {
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            return
        }
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
