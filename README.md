# SLATE

macOS tooling for editorial dailies: **ingest**, **proxy generation**, **audio sync**, **AI scoring**, and a **desktop app** with offline-first storage (GRDB) and optional cloud sync (Supabase + R2).

## Repository layout

| Path | Purpose |
|------|---------|
| `Package.swift` | SwiftPM **monorepo** manifest for all engine libraries and integration tests |
| `packages/` | Swift packages: `shared-types`, `sync-engine`, `ai-pipeline`, `ingest-daemon`, `export-writers` |
| `apps/desktop/` | **SLATE** macOS app (`SLATE.xcodeproj`, SwiftPM targets `SLATECore` / `SLATEUI`) |
| `apps/web/` | Web portal (if present) |
| `contracts/` | JSON API/data contracts + `storage.md` (R2 key conventions) |
| `supabase/` | SQL migrations and Edge Functions |
| `tests/IntegrationTests/` | SwiftPM integration tests (via root `Package.swift`) |
| `scripts/` | Build, test, desktop packaging, contract validation |
| `.github/workflows/` | CI (desktop build, benchmarks, security scans) |

## Prerequisites

- macOS 14+
- Xcode 15+ (Swift 5.9+)
- [jq](https://stedolan.github.io/jq/) and Node.js (for `scripts/check-versions.js` in CI)

## Build: engine packages (SwiftPM)

From this directory (the repo root), the unified `Package.swift` is the canonical layout for **integration tests** and cross-package development. Some targets may require a **clean compile pass** on `packages/shared-types` (Swift 6 concurrency and Accelerate imports) before `swift build` succeeds at the root; until then, build packages individually (below).

```bash
swift build -c release   # when the tree compiles cleanly
swift test
```

To build each package in isolation (as in CI):

```bash
(cd packages/sync-engine && swift build -c release && swift test)
(cd packages/ai-pipeline && swift build -c release && swift test)
(cd packages/ingest-daemon && swift build -c release && swift test)
```

Helper scripts:

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

Notarization and DMG steps are documented in `docs/code-signing.md` and `scripts/notarize-desktop-app.sh` / `scripts/package-desktop-dmg.sh`.

## Contracts & backend

- **Contracts:** `contracts/*.json` — validated in CI with `jq` and `node scripts/check-versions.js`.
- **Storage:** canonical R2 layout in `contracts/storage.md`.
- **Supabase:** `supabase/migrations/` and `supabase/functions/` (e.g. signed proxy URLs).

## Git

This repo is intended to be the **canonical** Git root for SLATE (see `docs/internal/GIT_AND_BRANCHES.md`). If your machine has a different Git repository (for example a parent home-directory repo), treat this folder as the project root for cloning, remotes, and CI.

## Documentation

- User-facing guide: `docs/USER_GUIDE.md`
- Code signing: `docs/code-signing.md`
- Internal notes: `docs/internal/`
