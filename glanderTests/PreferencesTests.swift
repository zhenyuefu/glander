import XCTest
@testable import glander

final class PreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "io.glander.tests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suiteName)
        // Ensure clean domain
        if let suiteName { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    }

    override func tearDown() {
        if let suiteName { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultValues() {
        let p = Preferences(defaults: defaults)
        XCTAssertEqual(p.windowAlpha, 0.9, accuracy: 0.0001)
        XCTAssertEqual(p.clickThrough, false)
        XCTAssertEqual(p.alwaysOnTop, true)
        XCTAssertEqual(p.bossKeyEnabled, true)
        XCTAssertEqual(p.marqueeEnabled, false)
        XCTAssertEqual(p.marqueeText.isEmpty, false)
        XCTAssertEqual(p.forceTransparentCSS, true)
        XCTAssertEqual(p.pdfAutoScrollEnabled, false)
        XCTAssertEqual(p.pdfAutoScrollSpeed, 40.0, accuracy: 0.01)
    }

    func testPersistence() {
        var p = Preferences(defaults: defaults)
        p.windowAlpha = 0.5
        p.clickThrough = true
        p.alwaysOnTop = false
        p.marqueeEnabled = true
        p.marqueeText = "测试文本"
        p.forceTransparentCSS = false
        p.pdfAutoScrollEnabled = true
        p.pdfAutoScrollSpeed = 66.0
        p.stocksSymbols = "AAPL, 510300"
        p.stocksDarkTheme = false
        p.bossKeyAction = 1
        p.camouflageStyle = "code"
        p.camouflageTitle = "Foo.swift"
        p.aiEnabled = true
        p.aiAction = 1
        p.aiCooldownSec = 8
        p.aiFPS = 3
        p.aiMinFrames = 3

        // Recreate to verify persisted values
        let p2 = Preferences(defaults: defaults)
        XCTAssertEqual(p2.windowAlpha, 0.5, accuracy: 0.0001)
        XCTAssertEqual(p2.clickThrough, true)
        XCTAssertEqual(p2.alwaysOnTop, false)
        XCTAssertEqual(p2.marqueeEnabled, true)
        XCTAssertEqual(p2.marqueeText, "测试文本")
        XCTAssertEqual(p2.forceTransparentCSS, false)
        XCTAssertEqual(p2.pdfAutoScrollEnabled, true)
        XCTAssertEqual(p2.pdfAutoScrollSpeed, 66.0, accuracy: 0.01)
        XCTAssertEqual(p2.stocksSymbols, "AAPL, 510300")
        XCTAssertEqual(p2.stocksDarkTheme, false)
        XCTAssertEqual(p2.bossKeyAction, 1)
        XCTAssertEqual(p2.camouflageStyle, "code")
        XCTAssertEqual(p2.camouflageTitle, "Foo.swift")
        XCTAssertEqual(p2.aiEnabled, true)
        XCTAssertEqual(p2.aiAction, 1)
        XCTAssertEqual(p2.aiCooldownSec, 8, accuracy: 0.01)
        XCTAssertEqual(p2.aiFPS, 3, accuracy: 0.01)
        XCTAssertEqual(p2.aiMinFrames, 3)
    }
}

