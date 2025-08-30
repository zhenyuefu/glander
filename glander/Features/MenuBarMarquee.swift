import AppKit

final class MenuBarMarquee {
    private weak var statusItem: NSStatusItem?
    private var timer: DispatchSourceTimer?
    private var buffer: [Character] = []
    private var stepInterval: TimeInterval = 0.15
    private var isRunning = false

    init(statusItem: NSStatusItem?) {
        self.statusItem = statusItem
    }

    func configure(text: String, charsPerSecond: Double) {
        // Build a looped buffer with spacing
        let t = text.isEmpty ? "" : text
        let spaced = "  " + t + "   •  " + t + "  "
        buffer = Array(spaced)
        stepInterval = max(0.05, 1.0 / max(1.0, charsPerSecond))
    }

    func start() {
        stop()
        guard let button = statusItem?.button else { return }
        if buffer.isEmpty { return }
        isRunning = true
        var idx = 0
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: stepInterval)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isRunning, !self.buffer.isEmpty else { return }
            // Rotate the buffer by one character
            let ch = self.buffer.removeFirst()
            self.buffer.append(ch)
            // Limit the visible window length to avoid overly long titles
            let sliceLen = min(28, self.buffer.count)
            let text = String(self.buffer.prefix(sliceLen))
            button.title = "📖 " + text
        }
        self.timer = timer
        timer.resume()
    }

    func stop(resetTitle: String? = nil) {
        isRunning = false
        timer?.cancel()
        timer = nil
        if let t = resetTitle {
            statusItem?.button?.title = t
        }
    }
}

