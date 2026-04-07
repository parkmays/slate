#!/usr/bin/env bash
# Ordered release gates from repo root (fail-fast). See docs/SHIPPING_RUNBOOK.md.
#
# Usage:
#   bash scripts/release-all.sh
#   DRY_RUN=1 bash scripts/release-all.sh
#   SKIP_DESKTOP=1 SKIP_WEB=1 bash scripts/release-all.sh
#
# Environment:
#   DRY_RUN=1              print commands only
#   SKIP_CONTRACTS=1       skip validate-contracts.sh
#   SKIP_SWIFT_ROOT=1      skip scripts/build-root-swift.sh
#   SKIP_WEB=1             skip scripts/release-web.sh
#   SKIP_DESKTOP=1         skip desktop packaging
#   SKIP_IOS=1             skip scripts/release-ios.sh --simulator-only
#   DESKTOP_NOTARIZE=1     run scripts/release-desktop.sh --release after DMG (requires Apple credentials)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DRY_RUN="${DRY_RUN:-0}"

run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

echo "==> SLATE release-all (repo root: $ROOT_DIR)"

if [[ "${SKIP_CONTRACTS:-0}" != "1" ]]; then
  if [[ -f "$ROOT_DIR/scripts/validate-contracts.sh" ]]; then
    run bash "$ROOT_DIR/scripts/validate-contracts.sh"
  else
    echo "==> (skip) validate-contracts.sh missing"
  fi
  run node "$ROOT_DIR/scripts/check-versions.js"
else
  echo "==> SKIP contracts / check-versions"
fi

if [[ "${SKIP_SWIFT_ROOT:-0}" != "1" ]]; then
  run bash "$ROOT_DIR/scripts/build-root-swift.sh" release
else
  echo "==> SKIP Swift root build"
fi

if [[ "${SKIP_WEB:-0}" != "1" ]]; then
  run bash "$ROOT_DIR/scripts/release-web.sh"
else
  echo "==> SKIP web"
fi

if [[ "${SKIP_DESKTOP:-0}" != "1" ]]; then
  run bash "$ROOT_DIR/scripts/build-desktop-app.sh" --release
  run bash "$ROOT_DIR/scripts/package-desktop-dmg.sh" --release
  if [[ "${DESKTOP_NOTARIZE:-0}" == "1" ]]; then
    run bash "$ROOT_DIR/scripts/release-desktop.sh" --release
  else
    echo "==> Desktop DMG built; set DESKTOP_NOTARIZE=1 to run notarization (scripts/release-desktop.sh)."
  fi
else
  echo "==> SKIP desktop"
fi

if [[ "${SKIP_IOS:-0}" != "1" ]]; then
  run bash "$ROOT_DIR/scripts/release-ios.sh" --simulator-only
else
  echo "==> SKIP iOS"
fi

echo "==> release-all complete"
