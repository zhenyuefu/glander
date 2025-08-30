Glander (macOS 透明摸鱼工具) — 项目骨架

目标
- 透明浮窗（网页/视频/PDF/小说/股票）与菜单栏控制。
- 全局老板键（默认 Cmd+Shift+H）一键显示/隐藏。
- 模块化架构，后续扩展 AI 摄像头检测、伪装模式等。

快速开始（Xcode 工程）
- 需求：macOS 12+，Xcode 15+。
- 打开 `glander.xcodeproj`，选择 `glander` 目标，按运行。
- 启动后：
  - 状态栏会出现 “GL”，菜单可显示/隐藏窗口或退出。
  - 老板键：按 `⌘⇧H` 切换透明窗口显示/隐藏。
  - 打开网页/小红书/PDF/视频/股票 在菜单中操作。

结构
- `glander/`：应用源码（AppDelegate、透明窗口、WebView、老板键等）。
  - `Core/TransparentWindow.swift`：透明窗口、置顶、穿透。
  - `Features/TransparentWebViewController.swift`：透明 `WKWebView`。
  - `Features/PDFViewerController.swift`：PDF 查看与自动滚动。
  - `Features/VideoPlayerController.swift`：视频播放器（含 PiP）。
  - `Features/StocksWidgetController.swift`：股票/基金跑马灯（TradingView）。
  - `Features/Camouflage/`：伪装界面（文档/代码）。
  - `Stealth/BossKeyManager.swift`：全局老板键注册与回调。
- `glanderTests/`、`glanderUITests/`：测试代码。

里程碑（对应实现顺序）
1) 透明窗口/穿透 + WebView 透明渲染（已含 Demo）
2) PDF/视频/小说/股票最小可用
3) 老板键完善与窗口分组保存/恢复
4) 伪装主题与菜单栏小说滚动
5) AI 摄像头检测（默认关闭）

注意
- 工程已改为使用现有 `glander` 目录的 Xcode 目标，遵循原有目录结构。
- 摄像头/麦克风等敏感权限默认不开启，AI 监控将在后续里程碑实现并默认关闭。
 - 启用 AI 摄像头检测前，请在 Target → Info 添加 `NSCameraUsageDescription` 说明文本。

测试
- 在 Xcode 中运行单元测试（Command+U），或执行：
  `xcodebuild test -project glander.xcodeproj -scheme glander -destination 'platform=macOS'`
- 详见 TESTING.md。
