# Repository Guidelines

## Project Structure & Module Organization
- `glander/`: macOS app source.
  - `Core/`: windowing, app-level infrastructure (e.g., `TransparentWindow.swift`).
  - `Features/`: user-facing modules (e.g., `TransparentWebViewController.swift`).
  - `Stealth/`: boss key, stealth utilities (e.g., `BossKeyManager.swift`).
  - `Assets.xcassets`, `glanderApp.swift`, `AppDelegate.swift`.
- `glanderTests/`, `glanderUITests/`: XCTest targets.
- `glander.xcodeproj/`: Xcode project.

## Build, Test, and Development Commands
- Build (Debug): `xcodebuild -project glander.xcodeproj -scheme glander -configuration Debug build`
- Run: Open in Xcode and run the `glander` scheme.
- Tests: `xcodebuild test -project glander.xcodeproj -scheme glander -destination 'platform=macOS'`
- First run notes: Ensure Target Membership is set for new files; link `WebKit.framework` and (optional) `Carbon.framework` if using the boss key.

## Continuous Integration
- GitHub Actions workflow: `.github/workflows/ci.yml`.
- Triggers on pushes/PRs to `main`/`master`; runs macOS build + tests.
- Uses `CODE_SIGNING_ALLOWED=NO` to avoid signing on CI.

## Coding Style & Naming Conventions
- Swift 5.9+/Xcode 15+; use Xcode defaults.
- Indentation: 4 spaces; line length ~120.
- Naming: UpperCamelCase for types/protocols; lowerCamelCase for methods/properties; `FeatureName/FileName.swift` mirrors type name.
- Structure: one primary type per file; group by folder (`Core`, `Features`, `Stealth`).

## Testing Guidelines
- Framework: XCTest.
- File naming: `*Tests.swift`; test methods start with `test` and assert behavior, not implementation details.
- Run locally in Xcode (Test navigator) or via `xcodebuild test`.
- Aim to cover critical window behavior (visibility, alpha, hotkey toggling) and regressions.

## Commit & Pull Request Guidelines
- Commits: present-tense, imperative, scoped prefixes when useful (e.g., `core:`, `features:`, `stealth:`). Example: `stealth: fix Carbon modifier flags casting`.
- PRs: clear description, screenshots/GIFs for UI changes, link issues, list validation steps (build, run, tests).
- Keep diffs focused; avoid unrelated refactors in feature/bugfix PRs.

## Security & Configuration Tips
- App Sandbox is enabled. For WebKit, enable `Outgoing Connections (Client)`.
- Optional: link `Carbon.framework` for global hotkey support; otherwise the boss key no-ops.
- When adding Web content, prefer HTTPS; configure ATS exceptions only if necessary.
