import AppKit
import WebKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: TransparentWindowController?
    private var webVC: TransparentWebViewController?
    private var pdfVC: PDFViewerController?
    private var videoVC: VideoPlayerController?
    private var stocksVC: StocksWidgetController?
    private var camera: CameraMonitor?
    private var pendingStocksApply: DispatchWorkItem?
    private var statusItem: NSStatusItem?
    private let bossKey = BossKeyManager()
    private var globalHotkeys: GlobalHotkeys?
    private let prefs = Preferences.shared
    private var cancellables = Set<AnyCancellable>()
    private var novelReader: MenuBarNovelReader?
    private var tocWC: NovelTOCWindowController?
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

    func applicationWillTerminate(_ notification: Notification) {
        // Explicitly cleanup monitors and hotkeys
        novelReader?.invalidate()
        globalHotkeys?.unregisterAll()
        bossKey.unregister()
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
        // Novel (TXT) controls in menu bar
        menu.addItem(withTitle: "小说 • 打开TXT…", action: #selector(openNovelTXT), keyEquivalent: "t")
        let prevItem = NSMenuItem(title: "小说 • 上一页 (⌥←)", action: #selector(novelPrev), keyEquivalent: "")
        let nextItem = NSMenuItem(title: "小说 • 下一页 (⌥→)", action: #selector(novelNext), keyEquivalent: "")
        menu.addItem(prevItem)
        menu.addItem(nextItem)
        // TOC submenu placeholder (will be built on demand)
        let tocItem = NSMenuItem(title: "小说 • 目录", action: nil, keyEquivalent: "")
        tocItem.submenu = NSMenu(title: "目录")
        menu.addItem(tocItem)
        menu.addItem(withTitle: "小说 • 目录窗口…", action: #selector(openNovelTOCWindow), keyEquivalent: "")
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

        // Setup novel reader
        novelReader = MenuBarNovelReader(statusItem: statusItem)
        // Ensure preferences bindings are active for hotkey changes
        if !didBindPrefs {
            bindPreferences()
            didBindPrefs = true
        }
        // Register global hotkeys from preferences
        registerNovelHotkeysFromPrefs()
        updateNovelMenuShortcutTitles()
        // Restore last reading if possible
        novelReader?.restoreLastReadingIfAvailable()
        rebuildTOCSubmenu()
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

        // Marquee removed; no bindings needed

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
        prefs.$stocksWidgetStyle
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
        prefs.$aiMinPersons
            .sink { [weak self] n in self?.camera?.minPersons = max(1, n) }
            .store(in: &cancellables)
        prefs.$aiDetectMode
            .sink { [weak self] mode in self?.camera?.detectMode = (mode == "human") ? .human : .face }
            .store(in: &cancellables)

        // Novel hotkey changes → re-register
        [
            prefs.$novelPrevKeyCode.map { _ in () }.eraseToAnyPublisher(),
            prefs.$novelPrevModifiers.map { _ in () }.eraseToAnyPublisher(),
            prefs.$novelNextKeyCode.map { _ in () }.eraseToAnyPublisher(),
            prefs.$novelNextModifiers.map { _ in () }.eraseToAnyPublisher(),
        ].forEach { pub in
            pub
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.registerNovelHotkeysFromPrefs() }
                .store(in: &cancellables)
        }
    }

    private func applyPreferencesToWindow() {
        guard let win = windowController?.window else { return }
        win.alphaValue = CGFloat(prefs.windowAlpha)
        win.ignoresMouseEvents = prefs.clickThrough
        win.level = prefs.alwaysOnTop ? .floating : .normal
    }

    // Marquee removed

    // MARK: - Novel (TXT) actions
    @objc private func openNovelTXT() {
        let panel = NSOpenPanel()
        // Use UTType-based filters to avoid deprecation warnings
        panel.allowedContentTypes = [
            UTType.plainText
        ].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            novelReader?.loadTXT(from: url)
            rebuildTOCSubmenu()
        }
    }

    @objc private func novelPrev() { novelReader?.pagePrev() }
    @objc private func novelNext() { novelReader?.pageNext() }

    @objc private func tocJump(_ sender: NSMenuItem) {
        if let offset = sender.representedObject as? Int { novelReader?.jumpTo(offset: offset) }
    }

    @objc private func openNovelTOCWindow() {
        guard let reader = novelReader else { return }
        if let wc = tocWC {
            wc.updateChapters(reader.toc)
            wc.showWindow(self)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            let wc = NovelTOCWindowController(chapters: reader.toc) { [weak self] offset in
                self?.novelReader?.jumpTo(offset: offset)
            }
            tocWC = wc
            wc.showWindow(self)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func rebuildTOCSubmenu() {
        guard let menu = statusItem?.menu else { return }
        // Find the TOC item by title inserted above
        if let tocItem = menu.items.first(where: { $0.title.hasPrefix("小说 • 目录") }) {
            tocItem.submenu = novelReader?.buildTOCMenu(target: self, action: #selector(tocJump(_:)))
        }
    }

    private func registerNovelHotkeysFromPrefs() {
        func mods(option: Bool, command: Bool, control: Bool, shift: Bool) -> GlobalHotkeys.Modifiers {
            var m = GlobalHotkeys.Modifiers(rawValue: 0)
            if option { m.insert(.option) }
            if command { m.insert(.command) }
            if control { m.insert(.control) }
            if shift { m.insert(.shift) }
            return m
        }
        if globalHotkeys == nil { globalHotkeys = GlobalHotkeys() }
        globalHotkeys?.unregisterAll()
        guard let gh = globalHotkeys else { return }
        // Resolve stored fields, fallback to Option+Arrow
        let defaultPrevCode: UInt32 = 123, defaultNextCode: UInt32 = 124
        let defaultMods = GlobalHotkeys.Modifiers.option
        let prevCode = prefs.novelPrevKeyCode == 0 ? defaultPrevCode : prefs.novelPrevKeyCode
        let nextCode = prefs.novelNextKeyCode == 0 ? defaultNextCode : prefs.novelNextKeyCode
        var prevMods = GlobalHotkeys.Modifiers(rawValue: prefs.novelPrevModifiers)
        if prevMods.rawValue == 0 { prevMods = defaultMods }
        var nextMods = GlobalHotkeys.Modifiers(rawValue: prefs.novelNextModifiers)
        if nextMods.rawValue == 0 { nextMods = defaultMods }

        var failed: [String] = []
        if !gh.registerRaw(keyCode: prevCode, modifiers: prevMods, { [weak self] in self?.novelReader?.pagePrev() }) {
            failed.append("上一页 (\(describeCombo(mods: prevMods, code: prevCode)))")
        }
        if !gh.registerRaw(keyCode: nextCode, modifiers: nextMods, { [weak self] in self?.novelReader?.pageNext() }) {
            failed.append("下一页 (\(describeCombo(mods: nextMods, code: nextCode)))")
        }
        if !failed.isEmpty {
            let message = "以下快捷键注册失败，可能与系统或其他应用冲突：\n\n" + failed.joined(separator: "、") + "\n\n请在偏好设置中更换修饰键。"
            showAlert(title: "快捷键冲突", message: message)
        }
        updateNovelMenuShortcutTitles()
    }

    private func updateNovelMenuShortcutTitles() {
        guard let menu = statusItem?.menu else { return }
        let defaultPrevCode: UInt32 = 123, defaultNextCode: UInt32 = 124
        let defaultMods = GlobalHotkeys.Modifiers.option
        let prevCode = prefs.novelPrevKeyCode == 0 ? defaultPrevCode : prefs.novelPrevKeyCode
        let nextCode = prefs.novelNextKeyCode == 0 ? defaultNextCode : prefs.novelNextKeyCode
        var prevMods = GlobalHotkeys.Modifiers(rawValue: prefs.novelPrevModifiers)
        if prevMods.rawValue == 0 { prevMods = defaultMods }
        var nextMods = GlobalHotkeys.Modifiers(rawValue: prefs.novelNextModifiers)
        if nextMods.rawValue == 0 { nextMods = defaultMods }
        let prevSym = describeCombo(mods: prevMods, code: prevCode)
        let nextSym = describeCombo(mods: nextMods, code: nextCode)
        for item in menu.items {
            if item.title.hasPrefix("小说 • 上一页") {
                item.title = "小说 • 上一页 (\(prevSym))"
            } else if item.title.hasPrefix("小说 • 下一页") {
                item.title = "小说 • 下一页 (\(nextSym))"
            }
        }
    }

    private func describeCombo(mods: GlobalHotkeys.Modifiers, code: UInt32) -> String {
        var s = ""
        if mods.contains(.option) { s += "⌥" }
        if mods.contains(.command) { s += "⌘" }
        if mods.contains(.control) { s += "⌃" }
        if mods.contains(.shift) { s += "⇧" }
        s += keyName(for: code)
        return s
    }

    private func keyName(for code: UInt32) -> String {
        switch code {
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 49: return "Space"
        case 53: return "Esc"
        case 36: return "Return"
        default: return "KeyCode \(code)"
        }
    }

    private func applyStocksPrefs() {
        // Coalesce rapid updates from multiple preference publishers (symbols/theme/style)
        pendingStocksApply?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.applyStocksPrefsNow()
        }
        pendingStocksApply = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: work)
    }

    private func applyStocksPrefsNow() {
        guard let vc = stocksVC else { return }
        let syms = prefs.stocksSymbols.split(separator: ",").map { String($0) }
        // Apply symbols/theme first, then style last to ensure a single final reload
        vc.symbols = syms
        vc.darkTheme = prefs.stocksDarkTheme
        if let style = StocksWidgetStyle(rawValue: prefs.stocksWidgetStyle) {
            vc.style = style
        }
        // If the stocks view is currently shown, refresh min size and clamp the frame
        if windowController?.contentViewController === vc, let win = windowController?.window {
            let min = vc.recommendedMinSize
            win.contentMinSize = min
            var frame = win.frame
            if frame.size.width < min.width { frame.size.width = min.width }
            if frame.size.height < min.height { frame.size.height = min.height }
            win.setFrame(frame, display: true)
        }
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
        if let style = StocksWidgetStyle(rawValue: prefs.stocksWidgetStyle) {
            vc.style = style
        }
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
        // Use UTType-based filters to avoid deprecated API warnings
        let exts = ["mp4", "mov", "m4v", "m3u8"]
        panel.allowedContentTypes = exts.compactMap { UTType(filenameExtension: $0) }
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
        // Clamp to a sensible minimum size per content to avoid content hidden below
        var minSize = NSSize(width: 600, height: 320)
        if let stocks = vc as? StocksWidgetController {
            minSize = stocks.recommendedMinSize
        }
        win.contentMinSize = minSize
        var target = previousFrame
        if target.size.width < minSize.width { target.size.width = minSize.width }
        if target.size.height < minSize.height { target.size.height = minSize.height }
        // Preserve current size but ensure at least the minimum for the content
        win.setFrame(target, display: true)
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
            cam.onRiskDetected = { [weak self] in
                Task { @MainActor in self?.handleAIRisk() }
            }
            cam.onPermissionProblem = { [weak self] message in
                Task { @MainActor in self?.showAlert(title: "摄像头不可用", message: message) }
            }
            cam.minConsecutiveDetections = prefs.aiMinFrames
            cam.targetFPS = prefs.aiFPS
            cam.minPersons = max(1, prefs.aiMinPersons)
            cam.detectMode = (prefs.aiDetectMode == "human") ? .human : .face
            camera = cam
        }
        camera?.minConsecutiveDetections = prefs.aiMinFrames
        camera?.targetFPS = prefs.aiFPS
        camera?.minPersons = max(1, prefs.aiMinPersons)
        camera?.detectMode = (prefs.aiDetectMode == "human") ? .human : .face
        camera?.start()
    }

    private func stopCameraMonitor() {
        camera?.stop()
    }

    private func handleAIRisk() {
        // Hide glander windows immediately; keep monitoring without cooldown
        if let win = windowController?.window, win.isVisible { win.orderOut(nil) }
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
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: since) {
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
