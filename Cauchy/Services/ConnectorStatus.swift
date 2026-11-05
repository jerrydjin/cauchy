import Foundation

/// Whether a connector can actually answer a question on this Mac right now.
enum ConnectorStatus: Equatable {
    /// Usable. The string is a short badge ("Ready", "On-device").
    case ready(String)
    /// A probe has not finished. The row looks usable and the chat stays quiet.
    /// Automatic does not treat this as evidence the connector can answer.
    case pending
    /// The probe failed, or one setup step is missing. `hint` is the sentence
    /// Settings can show. `note` is the short reason on the disabled menu row.
    case needsSetup(hint: String, note: String)
    /// Not usable on this machine, and not because of anything they skipped.
    case unavailable(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    /// A failed probe is not a choice. The row stays visible, greyed, with the
    /// short reason. An unfinished probe still looks selectable.
    var allowsSelection: Bool {
        switch self {
        case .ready, .pending: return true
        case .needsSetup, .unavailable: return false
        }
    }

    var badge: String {
        switch self {
        case .ready(let text): text
        case .pending: ""
        case .needsSetup: "Set up"
        case .unavailable: "Unavailable"
        }
    }

    /// The sentence Settings shows for an unusable connector. Nil while a
    /// probe is unfinished, so nothing says "Checking…".
    var hint: String? {
        switch self {
        case .ready, .pending: nil
        case .needsSetup(let hint, _): hint
        case .unavailable(let text): text
        }
    }

    /// Two or three words for a menu row. Nil when the row should show the name alone.
    var shortNote: String? {
        switch self {
        case .ready, .pending: nil
        case .needsSetup(_, let note): note
        case .unavailable: "unavailable"
        }
    }

    /// "Antigravity — Not signed in". The note is stored in lowercase.
    func menuTitle(name: String) -> String {
        guard let note = shortNote, !note.isEmpty else { return name }
        let reason = note.prefix(1).uppercased() + note.dropFirst()
        return "\(name) — \(reason)"
    }

    /// Picker and Settings status from a readiness value. Does not touch the
    /// store, so a snapshot and a test can name a failed probe without one.
    static func resolved(access: ConnectorAccess, name: String, readiness: ReadinessState) -> ConnectorStatus {
        switch access {
        case .onDevice:
            switch readiness {
            case .ready, .unknown, .checking:
                return .ready("On-device")
            case .blocked(let failure):
                switch failure {
                case .deviceNotEligible:
                    return .unavailable("This Mac isn't eligible for Apple Intelligence.")
                case .modelNotReady:
                    return .unavailable("The on-device model is still downloading.")
                case .intelligenceNotEnabled:
                    return .needsSetup(hint: failure.statusLine, note: "not enabled")
                default:
                    return .unavailable(failure.statusLine)
                }
            }
        case .cliSignIn, .apiKey:
            switch readiness {
            case .ready:
                return .ready("Ready")
            case .unknown, .checking:
                return .pending
            case .blocked(let failure):
                return .needsSetup(hint: failure.statusLine, note: failure.menuNote)
            }
        }
    }
}
