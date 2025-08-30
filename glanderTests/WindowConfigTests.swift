import XCTest
@testable import glander

final class WindowConfigTests: XCTestCase {
    func testTransparentWindowConfigDefaults() throws {
        let cfg = TransparentWindowConfig()
        XCTAssertEqual(cfg.initialAlpha, 0.95, accuracy: 0.0001)
        XCTAssertFalse(cfg.clickThrough)
    }
}

