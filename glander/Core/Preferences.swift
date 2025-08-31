import Foundation
import Combine

final class Preferences: ObservableObject {
    @MainActor static let shared = Preferences()

    @Published var windowAlpha: Double { didSet { save("windowAlpha", windowAlpha) } }
    @Published var clickThrough: Bool { didSet { save("clickThrough", clickThrough) } }
    @Published var alwaysOnTop: Bool { didSet { save("alwaysOnTop", alwaysOnTop) } }
    @Published var bossKeyEnabled: Bool { didSet { save("bossKeyEnabled", bossKeyEnabled) } }
    @Published var marqueeEnabled: Bool { didSet { save("marqueeEnabled", marqueeEnabled) } }
    @Published var marqueeText: String { didSet { save("marqueeText", marqueeText) } }
    /// characters per second
    @Published var marqueeSpeed: Double { didSet { save("marqueeSpeed", marqueeSpeed) } }
    @Published var forceTransparentCSS: Bool { didSet { save("forceTransparentCSS", forceTransparentCSS) } }
    @Published var customUserAgent: String { didSet { save("customUserAgent", customUserAgent) } }
    @Published var useEphemeralWebSession: Bool { didSet { save("useEphemeralWebSession", useEphemeralWebSession) } } // Incognito: do not persist cookies
    @Published var pdfAutoScrollEnabled: Bool { didSet { save("pdfAutoScrollEnabled", pdfAutoScrollEnabled) } }
    @Published var pdfAutoScrollSpeed: Double { didSet { save("pdfAutoScrollSpeed", pdfAutoScrollSpeed) } }
    @Published var stocksSymbols: String { didSet { save("stocksSymbols", stocksSymbols) } }
    @Published var stocksDarkTheme: Bool { didSet { save("stocksDarkTheme", stocksDarkTheme) } }
    @Published var stocksWidgetStyle: String { didSet { save("stocksWidgetStyle", stocksWidgetStyle) } }
    @Published var aiEnabled: Bool { didSet { save("aiEnabled", aiEnabled) } }
    @Published var aiCooldownSec: Double { didSet { save("aiCooldownSec", aiCooldownSec) } }
    @Published var aiFPS: Double { didSet { save("aiFPS", aiFPS) } }
    @Published var aiMinFrames: Int { didSet { save("aiMinFrames", aiMinFrames) } }

    // Novel reading progress
    @Published var novelLastOffset: Int { didSet { save("novelLastOffset", novelLastOffset) } }
    @Published var novelOffsets: [String: Int] { didSet { save("novelOffsets", novelOffsets) } }
    // Security-scoped bookmark for last opened TXT file
    @Published var novelLastFileBookmark: Data? { didSet {
        if let data = novelLastFileBookmark { defaults.set(data, forKey: "novelLastFileBookmark") } else { defaults.removeObject(forKey: "novelLastFileBookmark") }
    } }
    // Custom regex for chapter detection (one per line). Empty = use defaults only.
    @Published var novelTOCRegex: String { didSet { save("novelTOCRegex", novelTOCRegex) } }
    // Novel paging hotkeys (keyCode + modifiers). 0 means use default.
    @Published var novelPrevKeyCode: UInt32 { didSet { save("novelPrevKeyCode", Int(novelPrevKeyCode)) } }
    @Published var novelPrevModifiers: UInt32 { didSet { save("novelPrevModifiers", Int(novelPrevModifiers)) } }
    @Published var novelNextKeyCode: UInt32 { didSet { save("novelNextKeyCode", Int(novelNextKeyCode)) } }
    @Published var novelNextModifiers: UInt32 { didSet { save("novelNextModifiers", Int(novelNextModifiers)) } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.windowAlpha = defaults.object(forKey: "windowAlpha") as? Double ?? 0.9
        self.clickThrough = defaults.object(forKey: "clickThrough") as? Bool ?? false
        self.alwaysOnTop = defaults.object(forKey: "alwaysOnTop") as? Bool ?? true
        self.bossKeyEnabled = defaults.object(forKey: "bossKeyEnabled") as? Bool ?? true
        self.marqueeEnabled = defaults.object(forKey: "marqueeEnabled") as? Bool ?? false
        self.marqueeText = defaults.object(forKey: "marqueeText") as? String ?? "人在工位，心在江湖。"
        self.marqueeSpeed = defaults.object(forKey: "marqueeSpeed") as? Double ?? 6.0
        self.forceTransparentCSS = defaults.object(forKey: "forceTransparentCSS") as? Bool ?? false
        self.customUserAgent = defaults.object(forKey: "customUserAgent") as? String ?? ""
        self.useEphemeralWebSession = defaults.object(forKey: "useEphemeralWebSession") as? Bool ?? false // default to persistent (keep login)
        self.pdfAutoScrollEnabled = defaults.object(forKey: "pdfAutoScrollEnabled") as? Bool ?? false
        self.pdfAutoScrollSpeed = defaults.object(forKey: "pdfAutoScrollSpeed") as? Double ?? 40.0
        self.stocksSymbols = defaults.object(forKey: "stocksSymbols") as? String ?? "NASDAQ:AAPL, NASDAQ:TSLA, NASDAQ:MSFT"
        self.stocksDarkTheme = defaults.object(forKey: "stocksDarkTheme") as? Bool ?? true
        self.stocksWidgetStyle = defaults.object(forKey: "stocksWidgetStyle") as? String ?? "ticker"
        self.aiEnabled = defaults.object(forKey: "aiEnabled") as? Bool ?? false
        self.aiCooldownSec = defaults.object(forKey: "aiCooldownSec") as? Double ?? 10.0
        self.aiFPS = defaults.object(forKey: "aiFPS") as? Double ?? 4.0
        self.aiMinFrames = defaults.object(forKey: "aiMinFrames") as? Int ?? 2
        self.novelLastOffset = defaults.object(forKey: "novelLastOffset") as? Int ?? 0
        self.novelOffsets = defaults.object(forKey: "novelOffsets") as? [String: Int] ?? [:]
        self.novelLastFileBookmark = defaults.object(forKey: "novelLastFileBookmark") as? Data
        self.novelTOCRegex = defaults.object(forKey: "novelTOCRegex") as? String ?? ""
        // Defaults: 0 → will fallback to Option+Arrow in registration
        self.novelPrevKeyCode = UInt32(defaults.object(forKey: "novelPrevKeyCode") as? Int ?? 0)
        self.novelPrevModifiers = UInt32(defaults.object(forKey: "novelPrevModifiers") as? Int ?? 0)
        self.novelNextKeyCode = UInt32(defaults.object(forKey: "novelNextKeyCode") as? Int ?? 0)
        self.novelNextModifiers = UInt32(defaults.object(forKey: "novelNextModifiers") as? Int ?? 0)
    }

    private func save(_ key: String, _ value: Any) {
        defaults.set(value, forKey: key)
    }
}
