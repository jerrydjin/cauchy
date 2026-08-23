import AppKit
import SwiftUI

/// The marker colours a highlight can take. Stored by name rather than by
/// component values, so adjusting the palette repaints existing highlights
/// instead of stranding them on the old shade.
enum HighlightColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case yellow
    case green
    case blue
    case pink
    case purple

    static let `default` = HighlightColor.yellow

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .yellow: "Yellow"
        case .green: "Green"
        case .blue: "Blue"
        case .pink: "Pink"
        case .purple: "Purple"
        }
    }

    var swiftUIColor: Color {
        switch self {
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .pink: .pink
        case .purple: .purple
        }
    }

    /// What actually gets painted on the page. Alpha is applied by the caller:
    /// the active highlight is drawn a little stronger than the rest.
    var pageColor: NSColor {
        switch self {
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .blue: .systemBlue
        case .pink: .systemPink
        case .purple: .systemPurple
        }
    }
}
