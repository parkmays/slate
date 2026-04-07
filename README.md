# SLATE

macOS tooling for editorial dailies: **ingest**, **proxy generation**, **audio sync**, **AI scoring**, and a **desktop app** with offline-first storage (GRDB) and optional cloud sync (Supabase + R2).

## Repository layout

| Path | Purpose |
|------|---------|
| `Package.swift` | SwiftPM **monorepo** manifest for all engine libraries and integration tests |
| `packages/` | Swift packages: `shared-types`, `sync-engine`, `ai-pipeline`, `ingest-daemon`, `export-writers` |
| `apps/desktop/` | **SLATE** macOS app (`SLATE.xcodeproj`, SwiftPM targets `SLATECore` / `SLATEUI`) |
| `apps/web/` | Web portal (if present) |
| `apps/mobile-ios/` | **SLATE Mobile** iOS app (`SLATEMobile.xcodeproj`) |
| `contracts/` | JSON API/data contracts + `storage.md` (R2 key conventions) |
| `integrations/adobe-uxp-premiere/` | Optional **Premiere Pro UXP** panel (Frame.io V4 `GET /v4/me` probe; see `docs/ADOBE_INTEGRATION.md`) |
| `supabase/` | SQL migrations and Edge Functions |
| `tests/IntegrationTests/` | SwiftPM integration tests (via root `Package.swift`) |
| `scripts/` | Build, test, desktop packaging, contract validation |
| `.github/workflows/` | CI (web + Supabase, desktop, iOS, benchmarks, security scans) |

## Prerequisites

- macOS 14+
- Xcode 15+ (Swift 5.9+)
- [jq](https://stedolan.github.io/jq/) and Node.js (for `scripts/check-versions.js` in CI)

## Build: engine packages (SwiftPM)

From this directory (the repo root), the unified `Package.swift` is the canonical layout for **integration tests** and cross-package development. If `swift build` fails on the first try, build **`packages/shared-types`** first (same order CI uses), then build and test the root package:

```bash
bash scripts/build-root-swift.sh release
```

Equivalent manual steps:

```bash
(cd packages/shared-types && swift build -c release)
swift build -c release
swift test -c release
```

To build each package in isolation (as in per-package CI):

```bash
(cd packages/sync-engine && swift build -c release && swift test)
(cd packages/ai-pipeline && swift build -c release && swift test)
(cd packages/ingest-daemon && swift build -c release && swift test)
```

Other helper scripts:

```bash
./scripts/build.sh release
./scripts/test.sh all
```

## Build: desktop app (shipping)

**Xcode:** open `apps/desktop/SLATE.xcodeproj`, select the **SLATE** scheme, build (Release).

**CLI:** unsigned Release build and output under `dist/desktop/`:

```bash
bash scripts/build-desktop-app.sh --release
```

**DMG:** `bash scripts/package-desktop-dmg.sh --release` (builds the app, then creates `dist/desktop/SLATE-*.dmg`).

**Notarized release (local):** after signing credentials are configured, run `bash scripts/release-desktop.sh --release` to build, package a DMG, and submit the app + DMG to Apple notarytool (see `docs/code-signing.md`). Individual steps: `scripts/notarize-desktop-app.sh`, `scripts/package-desktop-dmg.sh`.

**Bundle ID:** the SwiftPM packaging script defaults to `com.mountaintop.slate` (`SLATE_DESKTOP_BUNDLE_ID`). Xcode’s **SLATE** target uses the same identifier in `SLATE.xcodeproj`; align with your Developer ID provisioning if you change it.

## Contracts & backend

- **Contracts:** `contracts/*.json` — validated in CI with `jq` and `node scripts/check-versions.js`.
- **Storage:** canonical R2 layout in `contracts/storage.md`.
- **Supabase:** `supabase/migrations/` and `supabase/functions/` (e.g. signed proxy URLs).

## Git

This repo is intended to be the **canonical** Git root for SLATE (see `docs/internal/GIT_AND_BRANCHES.md`). If your machine has a different Git repository (for example a parent home-directory repo), treat this folder as the project root for cloning, remotes, and CI.

## Documentation

- Shipping (desktop, web, iOS): `docs/SHIPPING_RUNBOOK.md` and `docs/RELEASE_CHECKLIST.md`
- ASC MHL vendor compatibility matrix: `docs/ASC_MHL_VENDOR_ACCEPTANCE_MATRIX.md`
- User-facing guide: `docs/USER_GUIDE.md`
- Code signing & notarized release: `docs/code-signing.md` (see also `scripts/release-desktop.sh`)
- NLE export QA checklist: `docs/EXPORT_NLE_VALIDATION.md`
- Platform 2.0 slice order: `docs/ROADMAP_PLATFORM_2.md`
- Web/desktop review & E2E: `docs/REVIEW_PARITY_AND_E2E.md`
- Adobe / Frame.io V4 / UXP: `docs/ADOBE_INTEGRATION.md`
- Internal notes: `docs/internal/`
