#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_SCRIPT="$ROOT_DIR/scripts/build-desktop-app.sh"

APP_NAME="${SLATE_DESKTOP_APP_NAME:-SLATE}"
OUTPUT_DIR="${SLATE_DESKTOP_OUTPUT_DIR:-$ROOT_DIR/dist/desktop}"
VERSION="${SLATE_DESKTOP_VERSION:-0.1.0}"
DMG_NAME="${SLATE_DESKTOP_DMG_NAME:-$APP_NAME-$VERSION.dmg}"
DMG_VOLUME_NAME="${SLATE_DESKTOP_DMG_VOLUME_NAME:-$APP_NAME Installer}"

if [[ ! -x "$BUILD_SCRIPT" ]]; then
  chmod +x "$BUILD_SCRIPT"
fi

"$BUILD_SCRIPT" "$@"

APP_PATH="$OUTPUT_DIR/$APP_NAME.app"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app bundle not found at $APP_PATH" >&2
  exit 1
fi

if ! command -v hdiutil >/dev/null 2>&1; then
  echo "hdiutil not found; DMG packaging requires macOS." >&2
  exit 1
fi

STAGING_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG_PATH"

echo "Creating DMG..."
hdiutil create \
  -volname "$DMG_VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo ""
echo "Created disk image:"
echo "  $DMG_PATH"
