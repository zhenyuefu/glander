# Testing

This repository uses XCTest with the built-in `glanderTests` target.

## Running Tests
- Xcode: Select the `glander` scheme, press Command+U, or run from the Test navigator.
- CLI: `xcodebuild test -project glander.xcodeproj -scheme glander -destination 'platform=macOS'`

## What’s Covered
- Preferences: defaults and persistence with `UserDefaults` (see `glanderTests/PreferencesTests.swift`).
- Window config: basic defaults for transparent window (see `glanderTests/WindowConfigTests.swift`).

UI-heavy and OS-integrated features (WebKit, AVKit, Camera, Carbon hotkeys) are intentionally not unit-tested here due to runtime environment and permissions. These are exercised via manual QA.

## Test Tips
- If tests fail to find symbols, ensure new files are part of the `glander` target (Target Membership).
- Disable noisy system logs: set `OS_ACTIVITY_MODE=disable` in the Run scheme.
- Camera tests are not included; to try camera features, add `NSCameraUsageDescription` to Target → Info and enable the “AI 风险监控” preference at runtime.
