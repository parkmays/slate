# SLATE Mobile (iOS)

SwiftUI shell for the SLATE iOS app. Open `SLATEMobile.xcodeproj` in Xcode 15+.

- **Bundle ID:** `com.mountaintop.slate.mobile` (align with your Apple Developer App ID).
- **Contracts:** API shapes live in the repo root [`../../contracts/`](../../contracts/) (e.g. `web-api.json`). This target does not bundle those files; point networking code at your production base URL and keep responses aligned with the JSON contracts.
- **Versioning:** Prefer aligning `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` with the repo root [`../../VERSION`](../../VERSION) when cutting releases. Use [`../../scripts/release-ios.sh`](../../scripts/release-ios.sh) for scripted builds.

## CI

GitHub Actions: `.github/workflows/ios-ci.yml` (build + unit tests on iOS Simulator).

## Distribution

See [`../../docs/SHIPPING_RUNBOOK.md`](../../docs/SHIPPING_RUNBOOK.md) and `ios-release.yml` for archive / TestFlight placeholders.
