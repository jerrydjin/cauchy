import Foundation

enum CLIAgentError: LocalizedError {
    case launchFailed(String)
    case timedOut
    case processFailed(exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "The assistant did not finish this request in time. Try again; completed work is saved."
        case .launchFailed(let message):
            return "Could not launch the CLI: \(message)"
        case .processFailed(let exitCode, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "The CLI exited with code \(exitCode)." : detail
        }
    }
}
