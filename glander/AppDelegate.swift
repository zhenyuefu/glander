import AppKit
import WebKit
import Combine
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: TransparentWindowController?
    private var webVC: TransparentWebViewController?
    private var pdfVC: PDFViewerController?
    private var videoVC: VideoPlayerController?
    private var stocksVC: StocksWidgetController?
    private var camera: CameraMonitor?
    private var aiCoolingDown = false
    private var aiCooldownWork: DispatchWorkItem?
    private var statusItem: NSStatusItem?
    private let bossKey = BossKeyManager()
    private let prefs = Preferences.shared
    private var cancellables = Set<AnyCancellable>()
    private var marquee: MenuBarMarquee?
    private var didBindPrefs = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure app runs as a regular app with visible windows
        NSApp.setActivationPolicy(.regular)
        setupMenuBar()
        setupBossKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        // 关闭应用级别的窗口/状态恢复，避免控制台 noisy 日志
        return false
    }

    private func setupWindow() {
        let config = TransparentWindowConfig(level: .floating, initialAlpha: 0.9, clickThrough: false)
        let controller = TransparentWindowController(config: config)
        controller.window?.title = "Glander"
        controller.window?.center()
        windowController = controller
        // Defer creating and showing content until user selects a menu action.
        if !didBindPrefs {
            bindPreferences()
            didBindPrefs = true
        }
    }

    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "GL"
        let menu = NSMenu()
        menu.addItem(withTitle: "偏好设置…", action: #selector(openPreferences), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "打开网页…", action: #selector(openURLPrompt), keyEquivalent: "o")
        menu.addItem(withTitle: "打开小红书探索", action: #selector(openXHSExplore), keyEquivalent: "")
        menu.addItem(withTitle: "打开股票/基金…", action: #selector(openStocks), keyEquivalent: "s")
        menu.addItem(withTitle: "打开PDF…", action: #selector(openPDFPrompt), keyEquivalent: "p")
        menu.addItem(withTitle: "打开视频URL…", action: #selector(openVideoURLPrompt), keyEquivalent: "u")
        menu.addItem(withTitle: "打开本地视频…", action: #selector(openLocalVideoPrompt), keyEquivalent: "v")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "清除网站数据…", action: #selector(clearWebsiteData), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "重置窗口外观", action: #selector(resetWindowAppearance), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "显示/隐藏窗口", action: #selector(toggleWindow), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "退出", action: #selector(quit), keyEquivalent: "q")
        item.menu = menu
        statusItem = item

        // Setup marquee if enabled
        marquee = MenuBarMarquee(statusItem: statusItem)
        applyMarqueeFromPrefs()
    }

    private func setupBossKey() {
        guard prefs.bossKeyEnabled else { return }
        bossKey.register(keyCode: .h, modifiers: [.command, .shift]) { [weak self] in
            guard let self else { return }
            self.toggleAllGlanderWindows()
        }
    }

    @objc private func toggleWindow() {
        toggleAllGlanderWindows()
    }

    private func toggleAllGlanderWindows() {
        // Only toggle existing window with content; do not create/show on first launch
        guard let win = windowController?.window, win.contentViewController != nil else { return }
        if win.isVisible {
            win.orderOut(nil)
        } else {
            windowController?.showWindow(self)
            ensureMainWindowVisible()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func openPreferences() {
        let wc = PreferencesWindowController.shared
        wc.showWindow(self)
        wc.window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // Camouflage feature removed

    private func bindPreferences() {
        // Window alpha
        prefs.$windowAlpha
            .sink { [weak self] _ in self?.applyPreferencesToWindow() }
            .store(in: &cancellables)

        // Click-through
        prefs.$clickThrough
            .sink { [weak self] _ in self?.applyPreferencesToWindow() }
            .store(in: &cancellables)

        // Always on top
        prefs.$alwaysOnTop
            .sink { [weak self] _ in self?.applyPreferencesToWindow() }
            .store(in: &cancellables)

        // Boss key enable/disable
        prefs.$bossKeyEnabled
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.setupBossKey()
                } else {
                    self.bossKey.unregister()
                }
            }
            .store(in: &cancellables)

        // Marquee bindings
        prefs.$marqueeEnabled
            .sink { [weak self] _ in self?.applyMarqueeFromPrefs() }
            .store(in: &cancellables)
        prefs.$marqueeText
            .sink { [weak self] _ in self?.applyMarqueeFromPrefs() }
            .store(in: &cancellables)
        prefs.$marqueeSpeed
            .sink { [weak self] _ in self?.applyMarqueeFromPrefs() }
            .store(in: &cancellables)

        // Web preferences
        prefs.$forceTransparentCSS
            .sink { [weak self] enabled in self?.webVC?.transparencyCSSEnabled = enabled }
            .store(in: &cancellables)
        prefs.$customUserAgent
            .sink { [weak self] ua in self?.webVC?.customUserAgent = (ua.isEmpty ? nil : ua) }
            .store(in: &cancellables)

        // PDF auto scroll
        prefs.$pdfAutoScrollEnabled
            .sink { [weak self] enabled in self?.pdfVC?.autoScrollEnabled = enabled }
            .store(in: &cancellables)
        prefs.$pdfAutoScrollSpeed
            .sink { [weak self] speed in self?.pdfVC?.autoScrollSpeed = speed }
            .store(in: &cancellables)

        // Stocks
        prefs.$stocksSymbols
            .sink { [weak self] _ in self?.applyStocksPrefs() }
            .store(in: &cancellables)
        prefs.$stocksDarkTheme
            .sink { [weak self] _ in self?.applyStocksPrefs() }
            .store(in: &cancellables)

        // AI Camera
        prefs.$aiEnabled
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled { self.startCameraMonitor() } else { self.stopCameraMonitor() }
            }
            .store(in: &cancellables)
        prefs.$aiFPS
            .sink { [weak self] fps in self?.camera?.targetFPS = fps }
            .store(in: &cancellables)
        prefs.$aiMinFrames
            .sink { [weak self] n in self?.camera?.minConsecutiveDetections = n }
            .store(in: &cancellables)
    }

    private func applyPreferencesToWindow() {
        guard let win = windowController?.window else { return }
        win.alphaValue = CGFloat(prefs.windowAlpha)
        win.ignoresMouseEvents = prefs.clickThrough
        win.level = prefs.alwaysOnTop ? .floating : .normal
    }

    private func applyMarqueeFromPrefs() {
        guard let marquee, let statusItem else { return }
        if prefs.marqueeEnabled {
            marquee.configure(text: prefs.marqueeText, charsPerSecond: prefs.marqueeSpeed)
            marquee.start()
        } else {
            marquee.stop(resetTitle: "GL")
            // ensure button shows base title
            statusItem.button?.title = "GL"
        }
    }

    private func applyStocksPrefs() {
        guard let vc = stocksVC else { return }
        let syms = prefs.stocksSymbols.split(separator: ",").map { String($0) }
        vc.symbols = syms
        vc.darkTheme = prefs.stocksDarkTheme
    }

    // MARK: - URL prompts
    @objc private func openURLPrompt() {
        guard let url = promptForURL(title: "打开网页", message: "输入一个链接 (https://…)") else { return }
        let wvc: TransparentWebViewController
        if let existing = webVC { wvc = existing } else {
            let newVC = TransparentWebViewController()
            newVC.transparencyCSSEnabled = prefs.forceTransparentCSS
            newVC.customUserAgent = prefs.customUserAgent.isEmpty ? nil : prefs.customUserAgent
            webVC = newVC
            wvc = newVC
        }
        setMainContent(wvc, title: "Glander • 网页")
        wvc.load(url: url)
        NSApp.activate(ignoringOtherApps: true)
    }

    

    @objc private func openXHSExplore() {
        guard let url = URL(string: "https://www.xiaohongshu.com/explore") else { return }
        let wvc: TransparentWebViewController
        if let existing = webVC { wvc = existing } else {
            let newVC = TransparentWebViewController()
            newVC.transparencyCSSEnabled = prefs.forceTransparentCSS
            newVC.customUserAgent = prefs.customUserAgent.isEmpty ? nil : prefs.customUserAgent
            webVC = newVC
            wvc = newVC
        }
        WebAdapters.apply(.xiaohongshu, to: wvc)
        setMainContent(wvc, title: "Glander • 网页")
        wvc.load(url: url)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openStocks() {
        let syms = prefs.stocksSymbols.split(separator: ",").map { String($0) }
        let vc: StocksWidgetController
        if let existing = stocksVC { vc = existing } else {
            let newVC = StocksWidgetController()
            stocksVC = newVC
            vc = newVC
        }
        vc.symbols = syms
        vc.darkTheme = prefs.stocksDarkTheme
        setMainContent(vc, title: "Glander • 股票/基金")
    }

    @objc private func openPDFPrompt() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            showPDF(url: url)
        }
    }

    @objc private func openVideoURLPrompt() {
        guard let url = promptForURL(title: "打开视频URL", message: "输入视频直链 (HLS/MP4 等)") else { return }
        showVideo(url: url)
    }

    @objc private func openLocalVideoPrompt() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["mp4", "mov", "m4v", "m3u8"]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            showVideo(url: url)
        }
    }

    private func promptForURL(title: String, message: String) -> URL? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(string: "https://")
        field.frame = NSRect(x: 0, y: 0, width: 340, height: 24)
        alert.accessoryView = field
        let resp = alert.runModal()
        guard resp == .alertFirstButtonReturn else { return nil }
        var text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text) else { return nil }
        return url
    }

    // MARK: - Presenters
    private func setMainContent(_ vc: NSViewController, title: String) {
        if windowController == nil { setupWindow() }
        guard let win = windowController?.window else { return }
        let previousFrame = win.frame
        windowController?.contentViewController = vc
        win.title = title
        // Always hide title bar and standard buttons for a frameless look
        applyWindowChrome(forWeb: true)
        // Apply window appearance preferences on first real content
        applyPreferencesToWindow()
        // Preserve the current window size to avoid unwanted shrinking
        win.setFrame(previousFrame, display: true)
        windowController?.showWindow(self)
        ensureMainWindowVisible()
    }

    /// Adjust window chrome: always no title bar, no close/minimize/zoom buttons.
    private func applyWindowChrome(forWeb: Bool) {
        guard let win = windowController?.window else { return }
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach { type in
            win.standardWindowButton(type)?.isHidden = true
        }
    }

    private func ensureMainWindowVisible() {
        guard let win = windowController?.window else { return }
        if !win.isVisible { windowController?.showWindow(self) }
        // If window somehow off-screen (e.g., display change), re-center
        let onAnyScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(win.frame) }
        if !onAnyScreen { win.center() }
        // Prevent fully invisible state
        if win.alphaValue < 0.1 {
            win.alphaValue = max(CGFloat(prefs.windowAlpha), 0.8)
        }
        // Bring to front and focus app
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Camouflage functions removed
    private func showPDF(url: URL) {
        let vc: PDFViewerController
        if let existing = pdfVC { vc = existing } else {
            let newVC = PDFViewerController()
            newVC.autoScrollEnabled = prefs.pdfAutoScrollEnabled
            newVC.autoScrollSpeed = prefs.pdfAutoScrollSpeed
            pdfVC = newVC
            vc = newVC
        }
        vc.open(url: url)
        setMainContent(vc, title: "Glander • PDF")
    }

    private func showVideo(url: URL) {
        let vc: VideoPlayerController
        if let existing = videoVC { vc = existing } else {
            let newVC = VideoPlayerController()
            videoVC = newVC
            vc = newVC
        }
        vc.load(url: url)
        setMainContent(vc, title: "Glander • 视频")
    }

    // MARK: - AI Camera
    private func startCameraMonitor() {
        if camera == nil {
            let cam = CameraMonitor()
            cam.onRiskDetected = { [weak self] in self?.handleAIRisk() }
            cam.onPermissionProblem = { [weak self] message in self?.showAlert(title: "摄像头不可用", message: message) }
            cam.minConsecutiveDetections = prefs.aiMinFrames
            cam.targetFPS = prefs.aiFPS
            camera = cam
        }
        camera?.minConsecutiveDetections = prefs.aiMinFrames
        camera?.targetFPS = prefs.aiFPS
        camera?.start()
    }

    private func stopCameraMonitor() {
        camera?.stop()
    }

    private func handleAIRisk() {
        if aiCoolingDown { return }
        aiCoolingDown = true
        // Action: hide all glander window(s)
        if let win = windowController?.window, win.isVisible { win.orderOut(nil) }
        // Cooldown: stop camera and restart after interval
        camera?.stop()
        aiCooldownWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.aiCoolingDown = false
            if self.prefs.aiEnabled { self.camera?.start() }
        }
        aiCooldownWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + prefs.aiCooldownSec, execute: work)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    // MARK: - Website Data
    @objc private func clearWebsiteData() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "清除网站数据"
        alert.informativeText = "这将删除 Cookie、缓存和本地存储，可能会退出所有已登录的网站。是否继续？"
        alert.addButton(withTitle: "清除")
        alert.addButton(withTitle: "取消")
        let resp = alert.runModal()
        guard resp == .alertFirstButtonReturn else { return }

        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let since = Date(timeIntervalSince1970: 0)
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: since) { [weak self] in
            DispatchQueue.main.async {
                let done = NSAlert()
                done.alertStyle = .informational
                done.messageText = "已清除网站数据"
                done.informativeText = "如需生效，请刷新网页或重新打开链接。"
                done.addButton(withTitle: "好")
                done.runModal()
            }
        }
    }

    // MARK: - Troubleshooting
    @objc private func resetWindowAppearance() {
        // Reset prefs-backed appearance
        prefs.windowAlpha = 1.0
        prefs.clickThrough = false
        prefs.alwaysOnTop = true
        applyPreferencesToWindow()
        // Ensure visibility and center
        ensureMainWindowVisible()
        windowController?.window?.center()
    }
}
