import Foundation

/// On-device Apple Intelligence is the only assistant that needs macOS 27.
/// The reader, hover previews, and the Claude / ChatGPT / Gemini connectors
/// stay available on the deployment target.
enum AppleIntelligenceAvailability {
    /// Menu note. Kept short so it fits a disabled provider row.
    static let unavailableNote = "Needs macOS 27"

    /// Shown in the ask field when no other provider is configured.
    static let chooseProviderMessage = "Choose Claude, ChatGPT, or Gemini in the model menu."

    static var isSupported: Bool {
        if #available(macOS 27, *) {
            return true
        }
        return false
    }
}
