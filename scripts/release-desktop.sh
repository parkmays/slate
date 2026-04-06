#!/usr/bin/env bash
# Build a DMG via package-desktop-dmg.sh, then notarize the app bundle and DMG.
#
# Prerequisites: Apple Developer credentials (see docs/code-signing.md).
# Environment mirrors scripts/notarize-desktop-app.sh and scripts/package-desktop-dmg.sh.
#
# Example:
#   SLATE_DESKTOP_CODESIGN_IDENTITY="Developer ID Application: …" \
#   SLATE_NOTARY_KEYCHAIN_PROFILE="notarytool-profile" \
#   bash scripts/release-desktop.sh --release

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTARY="$ROOT_DIR/scripts/notarize-desktop-app.sh"

if [[ ! -x "$ROOT_DIR/scripts/package-desktop-dmg.sh" ]]; then
  chmod +x "$ROOT_DIR/scripts/package-desktop-dmg.sh" || true
fi
if [[ ! -x "$NOTARY" ]]; then
  chmod +x "$NOTARY" || true
fi

"$ROOT_DIR/scripts/package-desktop-dmg.sh" "$@"

APP_NAME="${SLATE_DESKTOP_APP_NAME:-SLATE}"
OUTPUT_DIR="${SLATE_DESKTOP_OUTPUT_DIR:-$ROOT_DIR/dist/desktop}"
VERSION="${SLATE_DESKTOP_VERSION:-0.1.0}"
DMG_NAME="${SLATE_DESKTOP_DMG_NAME:-$APP_NAME-$VERSION.dmg}"

APP_PATH="$OUTPUT_DIR/$APP_NAME.app"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"

exec "$NOTARY" --app-path "$APP_PATH" --dmg-path "$DMG_PATH"
