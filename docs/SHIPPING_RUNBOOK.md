# SLATE shipping runbook

Canonical project root: this repository directory (contains `Package.swift`, `apps/`, `scripts/`).

This document ties together **desktop (macOS)**, **web**, and **iOS** release paths. Version source of truth for coordinated releases is the repo root [`VERSION`](../VERSION) file.

## Release baseline matrix

| Surface | Local preflight | CI workflow | Production artifact | Primary docs / scripts |
|--------|-----------------|-------------|---------------------|-------------------------|
| **Contracts + versions** | `bash scripts/validate-contracts.sh` (if present) or CI loop + `node scripts/check-versions.js` | [`ci.yml`](../.github/workflows/ci.yml) `validate-contracts` | N/A (gates only) | [`contracts/`](../contracts/) |
| **Swift engine (monorepo)** | `bash scripts/build-root-swift.sh release` | [`desktop-ci.yml`](../.github/workflows/desktop-ci.yml) root `swift test` | SwiftPM binaries under `.build` | [`README.md`](../README.md) |
| **Desktop app** | `bash scripts/build-desktop-app.sh --release`; DMG: `bash scripts/package-desktop-dmg.sh --release`; full notarized path: `bash scripts/release-desktop.sh --release` | [`desktop-ci.yml`](../.github/workflows/desktop-ci.yml) | `dist/desktop/SLATE-*.dmg` (local scripts); CI artifacts on `main` | [`docs/code-signing.md`](code-signing.md), [`scripts/release-desktop.sh`](../scripts/release-desktop.sh) |
| **Web portal** | `cd apps/web && npm ci && npm run type-check && npm run lint && npm run test && npm run build` | [`ci.yml`](../.github/workflows/ci.yml) `test-web`, `test-web-e2e`; [`web-ci.yml`](../.github/workflows/web-ci.yml) | Vercel production deploy (`deploy-web` in `ci.yml` on `main`) | [`apps/web/package.json`](../apps/web/package.json), [`scripts/release-web.sh`](../scripts/release-web.sh) |
| **Supabase** | `cd supabase && supabase db reset` (local) | [`ci.yml`](../.github/workflows/ci.yml) `test-supabase` | Migrations applied per your hosting process | [`supabase/`](../supabase/) |
| **iOS** | `bash scripts/release-ios.sh --simulator-only` (build/test without signing); device IPA: `bash scripts/release-ios.sh --archive-export` (requires signing) | [`ios-ci.yml`](../.github/workflows/ios-ci.yml) | IPA / TestFlight via [`ios-release.yml`](../.github/workflows/ios-release.yml) (manual dispatch; signing required for archive) | [`apps/mobile-ios/README.md`](../apps/mobile-ios/README.md), [`scripts/release-ios.sh`](../scripts/release-ios.sh) |

## Preflight (all targets)

Run from repo root unless noted.

1. **Branch / tag**: Confirm release branch is merged; tag format suggestion: `v$(cat VERSION)` (e.g. `v1.2.0`).
2. **Changelog**: Update [`CHANGELOG.md`](../CHANGELOG.md) and user-facing notes in [`RELEASE_NOTES.md`](../RELEASE_NOTES.md) as appropriate.
3. **Version alignment**:
   - Root [`VERSION`](../VERSION) drives coordinated messaging.
   - Web [`apps/web/package.json`](../apps/web/package.json) `version` should match product semver when you cut a web release.
   - Desktop: pass `SLATE_DESKTOP_VERSION` or rely on scripts’ defaults (see [`scripts/build-desktop-app.sh`](../scripts/build-desktop-app.sh)).
   - iOS: `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` — use [`scripts/release-ios.sh`](../scripts/release-ios.sh) env vars or Xcode.
4. **CI green**: Ensure `main` passes `CI/CD Pipeline`, `Desktop CI`, `Web CI`, and [`ios-ci.yml`](../.github/workflows/ios-ci.yml) for the commit you are releasing.
5. **Secrets inventory** (production):
   - **Vercel**: `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID` (see `ci.yml` `deploy-web`).
   - **Apple (desktop + iOS)**: Developer ID / App Store Connect API key or notary credentials as documented in [`docs/code-signing.md`](code-signing.md) and workflow files.
   - **iOS CI**: If the default simulator name is missing on a runner, set `SLATE_IOS_SIMULATOR_DESTINATION` locally or adjust the [`ios-ci.yml`](../.github/workflows/ios-ci.yml) destination string.
   - **iOS release (optional)**: `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID`, `APP_STORE_CONNECT_API_PRIVATE_KEY` for upload automation; distribution signing certificates/profiles for [`ios-release.yml`](../.github/workflows/ios-release.yml) (archive requires a valid signing setup).
   - **Slack** (optional): `SLACK_WEBHOOK_URL` for deploy notifications.

## Cut order (recommended)

Use [`scripts/release-all.sh`](../scripts/release-all.sh) for a fail-fast sequence, or run each gate manually:

1. **Backend contracts / Supabase** — merge migrations; run Supabase validation locally or rely on CI `test-supabase`.
2. **Web** — deploy when CI is green (`scripts/release-web.sh` or GitHub Actions production deploy).
3. **Desktop** — build, sign, notarize, publish DMG/update feed as applicable.
4. **iOS** — archive, export, upload to TestFlight / App Store per [`ios-release.yml`](../.github/workflows/ios-release.yml).

Order may change if a hotfix is web-only or desktop-only; document the exception in the release notes.

## Rollback

| Target | Rollback action |
|--------|------------------|
| **Web (Vercel)** | Promote previous production deployment in Vercel dashboard or redeploy prior Git SHA; ensure env vars unchanged. |
| **Desktop** | Keep previous DMG and optional Sparkle/update feed; re-point feed URL or publish a rollback build with restored version. |
| **iOS** | App Store: submit previous build or expedite a fix build; TestFlight: stop testing bad build and distribute last good build. |
| **Supabase** | Restore from backup or apply reverse migration in a controlled window; coordinate with API contract version in `contracts/`. |

## Post-release verification

- **Web**: Smoke test auth, review routes, API routes used by desktop/web.
- **Desktop**: Install DMG on a clean macOS VM; Gatekeeper / first launch.
- **iOS**: Install from TestFlight; critical flows.

## Orchestration scripts

| Script | Purpose |
|--------|---------|
| [`scripts/release-web.sh`](../scripts/release-web.sh) | Local web production checks; optional `vercel --prod` when CLI + token available |
| [`scripts/release-ios.sh`](../scripts/release-ios.sh) | Simulator build/test; archive/export when signing is configured |
| [`scripts/release-all.sh`](../scripts/release-all.sh) | Ordered release gates with `DRY_RUN=1` and `SKIP_*` env vars (see script header) |

`release-all` runs [`scripts/check-versions.js`](../scripts/check-versions.js); if contract semver fields differ across `contracts/*.json`, fix versions or run with `SKIP_CONTRACTS=1` for a partial gate (not recommended for production).

See also [`docs/RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md) for a printable checklist.
