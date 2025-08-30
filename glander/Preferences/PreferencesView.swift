import SwiftUI

struct PreferencesView: View {
    @ObservedObject var prefs = Preferences.shared

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
                Toggle("启用跑马灯", isOn: $prefs.marqueeEnabled)
                HStack {
                    Text("速度")
                    Slider(value: $prefs.marqueeSpeed, in: 2...14, step: 1)
                    Text(String(format: "%.0f字/秒", prefs.marqueeSpeed))
                        .frame(width: 90, alignment: .trailing)
                }
                TextField("文本", text: $prefs.marqueeText, prompt: Text("请输入要滚动的小说片段"))
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
                TextField("符号列表 (逗号分隔)", text: $prefs.stocksSymbols, prompt: Text("AAPL, TSLA, 510300"))
                Toggle("深色主题", isOn: $prefs.stocksDarkTheme)
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
                    Text("灵敏度")
                    Stepper(value: $prefs.aiMinFrames, in: 1...5) {
                        Text("连续 \(prefs.aiMinFrames) 帧")
                    }
                }
                HStack {
                    Text("帧率")
                    Slider(value: $prefs.aiFPS, in: 1...10, step: 1)
                    Text(String(format: "%.0f fps", prefs.aiFPS)).frame(width: 60, alignment: .trailing)
                }
                HStack {
                    Text("冷却")
                    Slider(value: $prefs.aiCooldownSec, in: 3...30, step: 1)
                    Text(String(format: "%.0f s", prefs.aiCooldownSec)).frame(width: 60, alignment: .trailing)
                }
                Text("注意：启用时摄像头指示灯会亮，需在 Target 的 Info 配置相机用途描述。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 420)
    }
}

#Preview {
    PreferencesView()
}
