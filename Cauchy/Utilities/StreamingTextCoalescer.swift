import Foundation

/// Rate-limits streamed partials to at most one flush per interval,
/// latest-value-wins. The first submit flushes immediately so the stream
/// paints without delay; later submits within the window are coalesced.
@MainActor
final class StreamingTextCoalescer {
    private let interval: Duration
    private var pending: String?
    private var cooldown: Task<Void, Never>?

    var onFlush: ((String) -> Void)?

    init(interval: Duration = .milliseconds(80)) {
        self.interval = interval
    }

    func submit(_ text: String) {
        if cooldown == nil {
            onFlush?(text)
            startCooldown()
        } else {
            pending = text
        }
    }

    /// Flushes any pending value immediately and stops the cooldown window.
    func flushNow() {
        cooldown?.cancel()
        cooldown = nil
        if let text = pending {
            pending = nil
            onFlush?(text)
        }
    }

    /// Drops any pending value and prevents further flushes until the next submit.
    func cancel() {
        cooldown?.cancel()
        cooldown = nil
        pending = nil
    }

    private func startCooldown() {
        cooldown = Task { [weak self, interval] in
            try? await Task.sleep(for: interval)
            guard let self, !Task.isCancelled else { return }
            self.cooldown = nil
            if let text = self.pending {
                self.pending = nil
                self.onFlush?(text)
                self.startCooldown()
            }
        }
    }
}
