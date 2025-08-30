import AppKit

struct TransparentWindowConfig {
    var level: NSWindow.Level
    var initialAlpha: CGFloat
    var clickThrough: Bool

    init(level: NSWindow.Level = .floating, initialAlpha: CGFloat = 0.95, clickThrough: Bool = false) {
        self.level = level
        self.initialAlpha = initialAlpha
        self.clickThrough = clickThrough
    }
}

final class TransparentWindowController: NSWindowController {
    init(config: TransparentWindowConfig) {
        let style: NSWindow.StyleMask = [.titled, .fullSizeContentView, .closable, .miniaturizable, .resizable]
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 480),
                              styleMask: style,
                              backing: .buffered,
                              defer: false)
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = true
        window.backgroundColor = .windowBackgroundColor
        window.hasShadow = true
        window.level = config.level
        window.alphaValue = config.initialAlpha
        window.ignoresMouseEvents = config.clickThrough
        // Note: .canJoinAllSpaces and .moveToActiveSpace are mutually exclusive.
        // Prefer moving to the active space and showing over fullscreen apps.
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.isRestorable = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
