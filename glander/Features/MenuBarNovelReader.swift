import AppKit

@MainActor
final class MenuBarNovelReader {
    private weak var statusItem: NSStatusItem?

    // Full text content and paging
    private var content: String = ""
    private var cursor: String.Index = "".startIndex
    private var lastVisibleCharCount: Int = 28 // dynamic page size based on width
    private let defaultMaxStatusWidth: CGFloat = 260
    private var didConfigureButton = false

    // Table of contents
    struct Chapter { let title: String; let charOffset: Int }
    private(set) var toc: [Chapter] = []

    // Key monitors (local to app)
    private var localKeyMonitor: Any?
    private let prefs = Preferences.shared
    private var currentFileURL: URL?

    init(statusItem: NSStatusItem?) {
        self.statusItem = statusItem
        installLocalKeyMonitor()
        updateTitle()
    }

    // Note: We avoid removing the local key monitor in deinit because
    // accessing actor-isolated state from a nonisolated deinit triggers
    // strict-concurrency diagnostics. The monitor handler captures self weakly,
    // so it becomes a no-op after this instance is deallocated.

    // MARK: - Public API
    func invalidate() {
        if let m = localKeyMonitor { NSEvent.removeMonitor(m) }
        localKeyMonitor = nil
    }

    func loadTXT(from url: URL) {
        var started = false
        if url.startAccessingSecurityScopedResource() { started = true }
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        do {
            let text = try decodeText(from: url)
            currentFileURL = url
            // Save bookmark for restore
            if let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                prefs.novelLastFileBookmark = data
            }
            setContent(text)
            // Restore per-file offset if any
            let key = fileKey(for: url)
            if let off = prefs.novelOffsets[key], off > 0 { jumpTo(offset: off) }
            // Persist last offset
            saveProgress()
        } catch {
            showAlert(title: "加载失败", message: "无法读取TXT小说：\(error.localizedDescription)")
        }
    }

    func clear() {
        content = ""
        cursor = content.startIndex
        toc = []
        updateTitle()
        saveProgress()
    }

    func pageNext() {
        guard !content.isEmpty else { return }
        let newIndex = advance(from: cursor, by: lastVisibleCharCount)
        if newIndex < content.endIndex {
            cursor = newIndex
        } else {
            cursor = content.index(content.endIndex, offsetBy: 0)
        }
        updateTitle()
        saveProgress()
    }

    func pagePrev() {
        guard !content.isEmpty else { return }
        cursor = retreat(from: cursor, by: lastVisibleCharCount)
        updateTitle()
        saveProgress()
    }

    func jumpTo(offset: Int) {
        guard !content.isEmpty else { return }
        let bounded = max(0, min(offset, content.count))
        cursor = indexAtCharacterOffset(bounded)
        updateTitle()
        saveProgress()
    }

    func buildTOCMenu(target: AnyObject, action: Selector) -> NSMenu {
        let menu = NSMenu()
        if toc.isEmpty {
            let item = NSMenuItem(title: "未检测到章节", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            return menu
        }
        for (i, ch) in toc.enumerated() {
            let title = String(format: "%03d · %@", i+1, ch.title)
            let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
            mi.representedObject = ch.charOffset
            mi.target = target
            menu.addItem(mi)
        }
        return menu
    }

    // MARK: - Private helpers
    func restoreLastReadingIfAvailable() {
        guard let data = prefs.novelLastFileBookmark else { return }
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
            loadTXT(from: url)
            // After loadTXT, jump to the last global offset as well
            if prefs.novelLastOffset > 0 { jumpTo(offset: prefs.novelLastOffset) }
        } catch {
            // If resolve fails, ignore silently
        }
    }

    private func setContent(_ text: String) {
        // Normalize line endings, trim obvious BOM/whitespace
        let t = text.replacingOccurrences(of: "\r\n", with: "\n")
                    .replacingOccurrences(of: "\r", with: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
        content = t
        cursor = content.startIndex
        toc = buildTOC(from: content)
        updateTitle()
    }

    private func updateTitle() {
        guard let button = statusItem?.button else { return }
        if !didConfigureButton {
            button.cell?.wraps = false
            didConfigureButton = true
        }
        if content.isEmpty {
            statusItem?.length = NSStatusItem.variableLength
            button.title = "GL"
            return
        }
        statusItem?.length = defaultMaxStatusWidth
        let count = visibleCharCount(from: cursor, button: button)
        lastVisibleCharCount = max(1, count)
        let end = advance(from: cursor, by: lastVisibleCharCount)
        let raw = String(content[cursor..<end])
        let sanitized = sanitize(raw)
        button.title = sanitized
    }

    private func advance(from idx: String.Index, by n: Int) -> String.Index {
        return content.index(idx, offsetBy: n, limitedBy: content.endIndex) ?? content.endIndex
    }

    private func retreat(from idx: String.Index, by n: Int) -> String.Index {
        return content.index(idx, offsetBy: -n, limitedBy: content.startIndex) ?? content.startIndex
    }

    private func indexAtCharacterOffset(_ offset: Int) -> String.Index {
        return content.index(content.startIndex, offsetBy: offset, limitedBy: content.endIndex) ?? content.endIndex
    }

    private func installLocalKeyMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] ev in
            guard let self else { return ev }
            let prevCode: UInt16 = UInt16(self.prefs.novelPrevKeyCode == 0 ? 123 : self.prefs.novelPrevKeyCode)
            let nextCode: UInt16 = UInt16(self.prefs.novelNextKeyCode == 0 ? 124 : self.prefs.novelNextKeyCode)
            let requiredPrev = self.requiredFlags(fromRaw: self.prefs.novelPrevModifiers)
            let requiredNext = self.requiredFlags(fromRaw: self.prefs.novelNextModifiers)
            if ev.keyCode == prevCode && self.event(ev, includes: requiredPrev) {
                self.pagePrev()
                return nil
            }
            if ev.keyCode == nextCode && self.event(ev, includes: requiredNext) {
                self.pageNext()
                return nil
            }
            return ev
        })
    }

    private func requiredFlags(fromRaw raw: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        let r = raw == 0 ? GlobalHotkeys.Modifiers.option.rawValue : raw
        if (r & GlobalHotkeys.Modifiers.option.rawValue) != 0 { flags.insert(.option) }
        if (r & GlobalHotkeys.Modifiers.command.rawValue) != 0 { flags.insert(.command) }
        if (r & GlobalHotkeys.Modifiers.control.rawValue) != 0 { flags.insert(.control) }
        if (r & GlobalHotkeys.Modifiers.shift.rawValue) != 0 { flags.insert(.shift) }
        return flags
    }

    private func event(_ ev: NSEvent, includes required: NSEvent.ModifierFlags) -> Bool {
        // All required flags must be present; ignore additional flags
        return required.isSubset(of: ev.modifierFlags)
    }

    private func visibleCharCount(from start: String.Index, button: NSStatusBarButton) -> Int {
        let configuredLen = statusItem?.length ?? defaultMaxStatusWidth
        let baseLen = (configuredLen <= 0) ? defaultMaxStatusWidth : configuredLen
        let maxWidth = max(40, baseLen - 8)
        let font = button.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let remaining = content.distance(from: start, to: content.endIndex)
        if remaining <= 4 { return remaining }
        var lo = 1
        var hi = min(remaining, 500)
        var best = 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let end = advance(from: start, by: mid)
            let raw = String(content[start..<end])
            let text = sanitize(raw)
            let width = (text as NSString).size(withAttributes: [.font: font]).width
            if width <= maxWidth {
                best = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return best
    }

    private func sanitize(_ s: String) -> String {
        if s.isEmpty { return s }
        // Replace line breaks, tabs with spaces and remove control chars
        let replaced = s.replacingOccurrences(of: "\r", with: " ")
                        .replacingOccurrences(of: "\n", with: " ")
                        .replacingOccurrences(of: "\t", with: " ")
        // Collapse multiple spaces
        let parts = replaced.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }

    private func buildTOC(from text: String) -> [Chapter] {
        var chapters: [Chapter] = []
        // Default chapter patterns
        let defaultPatternStrings = [
            #"^\s*第[一二三四五六七八九十百千0-9零两]+[章节卷回部集]\s*.*$"#,
            #"^\s*(?i:CHAPTER|Chapter)\s+([IVXLCDM]+|\d+)([\.:\-\s].*)?$"#
        ]
        var regexes: [NSRegularExpression] = []
        for p in defaultPatternStrings { if let r = try? NSRegularExpression(pattern: p, options: []) { regexes.append(r) } }
        let customLines = prefs.novelTOCRegex
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for p in customLines { if let r = try? NSRegularExpression(pattern: p, options: []) { regexes.append(r) } }

        let lines = text.components(separatedBy: .newlines)
        var offset = 0 // character offset
        outer: for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                for r in regexes {
                    let range = NSRange(location: 0, length: trimmed.utf16.count)
                    if r.firstMatch(in: trimmed, options: [], range: range) != nil {
                        chapters.append(Chapter(title: trimmed, charOffset: offset))
                        break
                    }
                }
            }
            // Advance offset by this line length + newline
            offset += line.count + 1
            if chapters.count > 2000 { break outer }
        }

        // If still empty, heuristically pick every ~2000 characters as pseudo chapters to allow jumping
        if chapters.isEmpty {
            let approx = max(1000, content.count / 50)
            var i = 0
            while i < content.count {
                chapters.append(Chapter(title: String(format: "位置 %d", i), charOffset: i))
                i += approx
                if chapters.count >= 50 { break }
            }
        }
        return chapters
    }

    private func saveProgress() {
        guard !content.isEmpty else { return }
        let offset = content.distance(from: content.startIndex, to: cursor)
        prefs.novelLastOffset = offset
        if let url = currentFileURL {
            let key = fileKey(for: url)
            var map = prefs.novelOffsets
            map[key] = offset
            prefs.novelOffsets = map
        }
    }

    private func fileKey(for url: URL) -> String {
        return url.standardizedFileURL.path
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    // MARK: - Encoding helpers for TXT (UTF-8/UTF-16/GBK/GB2312)
    private func decodeText(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if let s = decodeTextData(data) { return s }
        // As last resort use Foundation detector
        var converted: NSString? = nil
        var usedLossy = ObjCBool(false)
        let raw = NSString.stringEncoding(for: data, encodingOptions: [:], convertedString: &converted, usedLossyConversion: &usedLossy)
        if raw != 0, let str = converted as String? { return str }
        throw NSError(domain: "NovelReader", code: -1, userInfo: [NSLocalizedDescriptionKey: "未知编码或文件无法读取"])
    }

    private func decodeTextData(_ data: Data) -> String? {
        if data.count >= 3 && data.prefix(3) == Data([0xEF, 0xBB, 0xBF]) {
            return String(data: data, encoding: .utf8)
        }
        if data.count >= 2 {
            let b0 = data[0], b1 = data[1]
            if b0 == 0xFF && b1 == 0xFE, let s = String(data: data, encoding: .utf16LittleEndian) { return s }
            if b0 == 0xFE && b1 == 0xFF, let s = String(data: data, encoding: .utf16BigEndian) { return s }
        }
        var candidates: [String.Encoding] = [.utf8, .utf16LittleEndian, .utf16BigEndian]
        if let e = encoding(from: .GB_18030_2000) { candidates.append(e) }
        if let e = encoding(from: .GBK_95) { candidates.append(e) }
        if let e = encoding(from: .GB_2312_80) { candidates.append(e) }
        for enc in candidates { if let s = String(data: data, encoding: enc) { return s } }
        return nil
    }

    private func encoding(from cf: CFStringEncodings) -> String.Encoding? {
        let cfenc = CFStringEncoding(cf.rawValue)
        let ns = CFStringConvertEncodingToNSStringEncoding(cfenc)
        return String.Encoding(rawValue: ns)
    }
}
