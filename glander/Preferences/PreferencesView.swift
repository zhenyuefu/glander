import SwiftUI
import AppKit

struct PreferencesView: View {
    @ObservedObject var prefs = Preferences.shared
    // Hotkey capture handled in NovelHotkeyRecorder

    var body: some View {
        Form {
            Section(header: Text("窗口")) {
                HStack {
                    Text("透明度")
                    Slider(value: $prefs.windowAlpha, in: 0.3...1.0)
                    Text(String(format: "%.0f%%", prefs.windowAlpha * 100))
                        .frame(width: 50, alignment: .trailing)
                }
                Toggle("点击穿透", isOn: $prefs.clickThrough)
                Toggle("始终置顶", isOn: $prefs.alwaysOnTop)
            }

            Section(header: Text("老板键")) {
                Toggle("启用老板键 (⌘⇧H)", isOn: $prefs.bossKeyEnabled)
                Text("当前动作：显示/隐藏窗口（可见即隐藏，不可见即显示）")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(header: Text("菜单栏小说")) {
                Text("使用状态栏菜单加载 TXT 小说，并通过自定义全局快捷键翻页。默认：⌥←/⌥→。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("自定义章节匹配正则（每行一条，可用 (?i) 忽略大小写）：")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $prefs.novelTOCRegex)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 60)

                Divider()
                NovelHotkeyRecorder()
            }

            Section(header: Text("网页适配")) {
                Toggle("强制透明 CSS", isOn: $prefs.forceTransparentCSS)
                TextField("自定义 User-Agent (可选)", text: $prefs.customUserAgent, prompt: Text("例如 Safari UA"))
                Toggle("无痕模式（不保留登录）", isOn: $prefs.useEphemeralWebSession)
                Text("关闭无痕即可保持登录状态，改动在新开网页时生效。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(header: Text("PDF")) {
                Toggle("自动滚动", isOn: $prefs.pdfAutoScrollEnabled)
                HStack {
                    Text("速度")
                    Slider(value: $prefs.pdfAutoScrollSpeed, in: 10...120, step: 5)
                    Text(String(format: "%.0f pt/s", prefs.pdfAutoScrollSpeed))
                        .frame(width: 80, alignment: .trailing)
                }
            }

            Section(header: Text("股票/基金")) {
                TextField("符号列表 (逗号分隔)", text: $prefs.stocksSymbols, prompt: Text("NASDAQ:AAPL, NASDAQ:TSLA, 510300"))
                Toggle("深色主题", isOn: $prefs.stocksDarkTheme)
                Picker("样式", selection: $prefs.stocksWidgetStyle) {
                    Text("跑马灯").tag("ticker")
                    Text("概览").tag("overview")
                    Text("单只").tag("single")
                }
                Text("使用 TradingView 嵌入，仅作展示用途")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Camouflage removed

            Section(header: Text("AI 风险监控")) {
                Toggle("启用摄像头检测（仅本地处理）", isOn: $prefs.aiEnabled)
                Text("检测到风险时将隐藏窗口")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("检测类型")
                    Picker("检测类型", selection: $prefs.aiDetectMode) {
                        Text("人脸").tag("face")
                        Text("人体").tag("human")
                    }
                    .pickerStyle(.segmented)
                }
                HStack {
                    Text("灵敏度")
                    Stepper(value: $prefs.aiMinFrames, in: 1...5) {
                        Text("连续 \(prefs.aiMinFrames) 帧")
                    }
                }
                HStack {
                    Text("人数阈值")
                    Stepper(value: $prefs.aiMinPersons, in: 1...5) {
                        Text("至少 \(prefs.aiMinPersons) 人")
                    }
                }
                HStack {
                    Text("帧率")
                    Slider(value: $prefs.aiFPS, in: 1...10, step: 1)
                    Text(String(format: "%.0f fps", prefs.aiFPS)).frame(width: 60, alignment: .trailing)
                }
                // Removed cooldown: camera keeps monitoring continuously
                Text("注意：启用时摄像头指示灯会亮，需在 Target 的 Info 配置相机用途描述。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 420)
        // No local capture here; see NovelHotkeyRecorder
    }
}

#Preview {
    PreferencesView()
}

// MARK: - Hotkey recorder UI
struct NovelHotkeyRecorder: View {
    @ObservedObject var prefs = Preferences.shared
    @State private var captureTarget: CaptureTarget? = nil
    @State private var monitor: Any? = nil
    @State private var prevStatus: String = ""
    @State private var nextStatus: String = ""

    enum CaptureTarget { case prev, next }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("翻页快捷键")
                .font(.subheadline)
            HStack {
                Text("上一页：")
                Text(displayCombo(code: prefs.novelPrevKeyCode == 0 ? 123 : prefs.novelPrevKeyCode,
                                   mods: prefs.novelPrevModifiers))
                    .font(.system(.body, design: .monospaced))
                    .frame(minWidth: 140, alignment: .leading)
                Button(captureTarget == .prev ? "按下组合…" : "录制") { captureTarget = .prev }
                Text(prevStatus).foregroundStyle(.secondary).font(.footnote)
            }
            HStack {
                Text("下一页：")
                Text(displayCombo(code: prefs.novelNextKeyCode == 0 ? 124 : prefs.novelNextKeyCode,
                                   mods: prefs.novelNextModifiers))
                    .font(.system(.body, design: .monospaced))
                    .frame(minWidth: 140, alignment: .leading)
                Button(captureTarget == .next ? "按下组合…" : "录制") { captureTarget = .next }
                Text(nextStatus).foregroundStyle(.secondary).font(.footnote)
            }
            Text("提示：某些系统快捷键可能占用组合，如注册失败，请更换组合。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .onChange(of: captureTarget) { _, newValue in
            if newValue != nil { startCapture() } else { stopCapture() }
        }
    }

    private func startCapture() {
        stopCapture()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { ev in
            guard let target = captureTarget else { return ev }
            let mods = modifiers(from: ev.modifierFlags)
            let code = UInt32(ev.keyCode)

            // Save to prefs
            switch target {
            case .prev:
                prefs.novelPrevKeyCode = code
                prefs.novelPrevModifiers = mods.rawValue
                prevStatus = testRegister(code: code, mods: mods) ? "已注册" : "冲突"
            case .next:
                prefs.novelNextKeyCode = code
                prefs.novelNextModifiers = mods.rawValue
                nextStatus = testRegister(code: code, mods: mods) ? "已注册" : "冲突"
            }
            captureTarget = nil
            return nil // consume
        }
    }

    private func stopCapture() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }

    private func modifiers(from flags: NSEvent.ModifierFlags) -> GlobalHotkeys.Modifiers {
        var m = GlobalHotkeys.Modifiers(rawValue: 0)
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.command) { m.insert(.command) }
        if flags.contains(.control) { m.insert(.control) }
        if flags.contains(.shift) { m.insert(.shift) }
        // If none pressed, default to Option for convenience
        if m.rawValue == 0 { m.insert(.option) }
        return m
    }

    private func displayCombo(code: UInt32, mods: UInt32) -> String {
        var s = ""
        let m = GlobalHotkeys.Modifiers(rawValue: mods == 0 ? GlobalHotkeys.Modifiers.option.rawValue : mods)
        if m.contains(.option) { s += "⌥" }
        if m.contains(.command) { s += "⌘" }
        if m.contains(.control) { s += "⌃" }
        if m.contains(.shift) { s += "⇧" }
        s += keyName(for: code)
        return s
    }

    private func keyName(for code: UInt32) -> String {
        switch code {
        case 0: return "←"
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

    private func testRegister(code: UInt32, mods: GlobalHotkeys.Modifiers) -> Bool {
        let tester = GlobalHotkeys()
        let ok = tester.registerRaw(keyCode: code, modifiers: mods, {})
        tester.unregisterAll()
        return ok
    }
}
