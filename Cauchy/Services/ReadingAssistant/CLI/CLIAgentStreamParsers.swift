import Foundation

/// Incremental parser over one CLI run's stdout JSONL.
/// `consume` returns the updated visible text whenever it changed.
protocol CLIAgentStreamParsing {
    mutating func consume(line: String) -> String?
    var finalText: String? { get }
    var errorMessage: String? { get }
}

private func jsonObject(from line: String) -> [String: Any]? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

/// Parses `claude -p --output-format stream-json --include-partial-messages`.
/// Observed shapes (Claude Code 2.1.x):
///   {"type":"system","subtype":"init",...}
///   {"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"..."}}}
///   {"type":"assistant","message":{"content":[{"type":"text","text":"..."}]},"error":"authentication_failed"?}
///   {"type":"result","subtype":"success","is_error":false,"result":"..."}
struct ClaudeCodeStreamParser: CLIAgentStreamParsing {
    private var accumulated = ""
    private var snapshotText: String?
    private(set) var finalText: String?
    private(set) var errorMessage: String?

    mutating func consume(line: String) -> String? {
        guard let object = jsonObject(from: line),
              let type = object["type"] as? String else { return nil }

        switch type {
        case "stream_event":
            guard let event = object["event"] as? [String: Any],
                  event["type"] as? String == "content_block_delta",
                  let delta = event["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String,
                  !text.isEmpty else { return nil }
            accumulated += text
            return accumulated

        case "assistant":
            guard let message = object["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { return nil }
            let text = content
                .compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                .joined(separator: "\n\n")
            if let error = object["error"] as? String, !error.isEmpty {
                errorMessage = text.isEmpty ? error : text
                return nil
            }
            guard !text.isEmpty else { return nil }
            snapshotText = text
            // Snapshots trail the deltas; only surface one if it's ahead.
            if text.utf16.count > accumulated.utf16.count {
                accumulated = text
                return accumulated
            }
            return nil

        case "result":
            if object["is_error"] as? Bool == true {
                errorMessage = (object["result"] as? String) ?? "Claude Code returned an error."
            } else {
                let result = (object["result"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                finalText = (result?.isEmpty == false ? result : nil) ?? snapshotText ?? (accumulated.isEmpty ? nil : accumulated)
            }
            return nil

        default:
            return nil
        }
    }
}

/// Parses `codex exec --json`. Codex's JSONL protocol has shifted between
/// releases, so this recognizes both known shapes and degrades gracefully:
///   A: {"id":"...","msg":{"type":"agent_message","message":"..."}}
///      {"id":"...","msg":{"type":"agent_message_delta","delta":"..."}}
///      {"id":"...","msg":{"type":"error","message":"..."}}
///   B: {"type":"item.completed","item":{"type"|"item_type":"agent_message","text":"..."}}
///      {"type":"error","message":"..."}
struct CodexStreamParser: CLIAgentStreamParsing {
    private var completedMessages: [String] = []
    private var pendingText = ""
    private(set) var errorMessage: String?

    var finalText: String? {
        let text = currentText
        return text.isEmpty ? nil : text
    }

    private var currentText: String {
        var parts = completedMessages
        if !pendingText.isEmpty {
            parts.append(pendingText)
        }
        return parts.joined(separator: "\n\n")
    }

    mutating func consume(line: String) -> String? {
        guard let object = jsonObject(from: line) else { return nil }

        // Shape A: event envelope under "msg".
        if let msg = object["msg"] as? [String: Any], let type = msg["type"] as? String {
            switch type {
            case "agent_message_delta":
                if let delta = msg["delta"] as? String, !delta.isEmpty {
                    pendingText += delta
                    return currentText
                }
            case "agent_message":
                if let message = msg["message"] as? String, !message.isEmpty {
                    completedMessages.append(message)
                    pendingText = ""
                    return currentText
                }
            case "error":
                errorMessage = (msg["message"] as? String) ?? "Codex returned an error."
            default:
                break
            }
            return nil
        }

        // Shape B: typed items.
        guard let type = object["type"] as? String else { return nil }
        if type == "error" {
            errorMessage = (object["message"] as? String) ?? "Codex returned an error."
            return nil
        }
        guard type.hasPrefix("item."),
              let item = object["item"] as? [String: Any] else { return nil }
        let itemType = (item["type"] as? String) ?? (item["item_type"] as? String)
        guard itemType == "agent_message",
              let text = item["text"] as? String,
              !text.isEmpty else { return nil }

        if type == "item.completed" {
            completedMessages.append(text)
            pendingText = ""
        } else {
            pendingText = text
        }
        return currentText
    }
}
