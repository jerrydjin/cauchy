import XCTest
@testable import Cauchy

@MainActor
final class ConnectorSetupTests: XCTestCase {
    func testAntigravityInstallerUsesSupportedArguments() throws {
        let installer = try XCTUnwrap(ConnectorSetupService.installer(for: .antigravity))
        XCTAssertEqual(installer.url, "https://antigravity.google/cli/install.sh")
        XCTAssertEqual(installer.shell, "/bin/bash")
        XCTAssertEqual(installer.arguments, [])
    }

    func testClaudeStatusRequiresExplicitAuthentication() {
        XCTAssertTrue(ConnectorSetupService.claudeIsSignedIn(#"{"loggedIn":true}"#))
        XCTAssertFalse(ConnectorSetupService.claudeIsSignedIn(#"{"loggedIn":false}"#))
        XCTAssertFalse(ConnectorSetupService.claudeIsSignedIn("Usage: claude auth status"))
        XCTAssertFalse(ConnectorSetupService.claudeIsSignedIn(#"{"loggedIn":"true"}"#))
    }

    func testFailedInstallerCannotAdvanceAsSuccess() async {
        let service = ConnectorSetupService()
        do {
            _ = try await service.run(URL(fileURLWithPath: "/bin/sh"), ["-c", "exit 23"], timeout: 2)
            XCTFail("Nonzero installer exit must fail")
        } catch let error as CLIAgentError {
            guard case .processFailed(let code, _) = error else { return XCTFail("Unexpected error") }
            XCTAssertEqual(code, 23)
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    func testHungSetupTimesOut() async {
        let service = ConnectorSetupService()
        let start = Date()
        do {
            _ = try await service.run(URL(fileURLWithPath: "/bin/sleep"), ["30"], timeout: 0.1)
            XCTFail("Hung process must time out")
        } catch {
            XCTAssertLessThan(Date().timeIntervalSince(start), 3)
        }
    }

    func testCancellingSetupDoesNotReportSuccess() async {
        let service = ConnectorSetupService()
        let task = Task {
            try await service.run(URL(fileURLWithPath: "/bin/sleep"), ["30"], timeout: 60)
        }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancellation must propagate")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
}

final class ModelCatalogTests: XCTestCase {
    func testRetiredChoicesKeepTheirCapabilityTier() {
        let cases: [(AssistantConnectorID, String, String)] = [
            (.codex, "gpt-5.6-sol", "gpt-6-astra"),
            (.codex, "gpt-5.6-terra", "gpt-6-sol"),
            (.codex, "gpt-5.6-luna", "gpt-6-luna"),
            (.openaiAPI, "gpt-5.6-sol", "gpt-6-astra"),
            (.anthropicAPI, "claude-opus-5", "claude-opus-5-5"),
            (.gemini, "gemini-3.6-flash", "gemini-3.7-flash"),
            (.gemini, "gemini-3.7-flash-lite", "gemini-3.5-flash-lite"),
        ]

        for (connectorID, storedID, expectedID) in cases {
            XCTAssertEqual(connectorID.connector.choice(fromToken: storedID), .model(expectedID))
        }
    }

    func testCurrentGeminiChoiceRemainsPinnedAndNewDefaultIsLatest() {
        let connector = AssistantConnectorID.gemini.connector
        XCTAssertEqual(connector.choice(fromToken: "gemini-3.7-flash"), .model("gemini-3.7-flash"))
        XCTAssertEqual(connector.defaultChoice, .model("gemini-3.8-flash"))
    }
}
