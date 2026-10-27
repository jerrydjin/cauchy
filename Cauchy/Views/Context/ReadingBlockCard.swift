import SwiftUI

/// Typeset statement for the reference pane. The pane supplies the heading;
/// this view does not add a title or a second surface.
struct ReadingBlockCard: View {
    let displayBody: String

    var body: some View {
        // Statements are prose. A stray backtick or a formula SwiftMath cannot
        // draw must not flip the rest of the sentence into monospace.
        MessageContentView(content: displayBody, font: .body, allowsMonospace: false)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
