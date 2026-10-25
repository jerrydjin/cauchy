import SwiftUI

/// Typeset statement for the reference pane. The pane supplies the heading;
/// this view does not add a title or a second surface.
struct ReadingBlockCard: View {
    let displayBody: String

    var body: some View {
        MessageContentView(content: displayBody, font: .body)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
