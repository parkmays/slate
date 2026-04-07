# Release checklist

Use per release train. Check boxes as you complete each step.

## Before merge to release branch

- [ ] [`VERSION`](../VERSION) updated (if shipping a new semver).
- [ ] [`CHANGELOG.md`](../CHANGELOG.md) updated.
- [ ] [`RELEASE_NOTES.md`](../RELEASE_NOTES.md) updated for user-visible changes.
- [ ] `apps/web/package.json` version aligned (if shipping web).
- [ ] Contracts validated: `bash scripts/validate-contracts.sh` and `node scripts/check-versions.js` from repo root (requires Node). If `check-versions.js` reports a semver mismatch across `contracts/*.json`, resolve before shipping or document an intentional exception.
- [ ] CI considered green for the SHA you will tag.

## Supabase / API

- [ ] Migrations reviewed under `supabase/migrations/`.
- [ ] Staging or local `supabase db reset` succeeded (optional but recommended).
- [ ] No unintended `contracts/*.json` drift vs server behavior.

## Web (`apps/web`)

- [ ] `npm ci && npm run type-check && npm run lint && npm run test && npm run build`
- [ ] E2E: `npm run test:e2e` (or rely on CI `test-web-e2e`).
- [ ] Vercel env vars match production (`NEXT_PUBLIC_*`, server secrets).
- [ ] After deploy: smoke test production URL.

## Desktop (macOS)

- [ ] `bash scripts/build-root-swift.sh release` (or CI parity).
- [ ] `bash scripts/build-desktop-app.sh --release` (unsigned OK for internal).
- [ ] ASC MHL acceptance checks reviewed for offload/verification releases (see [`docs/ASC_MHL_VENDOR_ACCEPTANCE_MATRIX.md`](ASC_MHL_VENDOR_ACCEPTANCE_MATRIX.md)).
- [ ] For external distribution: `bash scripts/release-desktop.sh --release` with signing/notary env (see [`docs/code-signing.md`](code-signing.md)).
- [ ] DMG smoke test; `spctl` / Gatekeeper as needed.
- [ ] Checksum or hosting URL for download page updated.

## iOS (`apps/mobile-ios`)

- [ ] `bash scripts/release-ios.sh --simulator-only` passes locally.
- [ ] Version/build numbers set for App Store Connect.
- [ ] Signing: Xcode team + certificates; or CI secrets for `ios-release.yml`.
- [ ] TestFlight validation on device.
- [ ] App Store metadata / review notes if public release.

## Tag and communicate

- [ ] Git tag: `v<VERSION>` pushed.
- [ ] Internal announcement (Slack/email) with rollback owner.
- [ ] Monitor errors/logs for first 24h.

## Rollback ready

- [ ] Previous web deployment ID noted (Vercel).
- [ ] Previous desktop artifact retained.
- [ ] iOS: previous build number known in App Store Connect.
