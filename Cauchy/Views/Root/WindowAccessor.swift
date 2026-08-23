import AppKit
import SwiftUI

/// Hands the hosting `NSWindow` back to SwiftUI. Needed because a workspace
/// sometimes has to act on its own window — bringing a document's window
/// forward when a second open lands on it, or closing a window that opened for
/// a document another one already has.
struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // The view has no window until it is in the hierarchy, which is one
        // run-loop turn after this call.
        DispatchQueue.main.async { onWindow(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onWindow(nsView.window) }
    }
}
