#!/usr/bin/env bash
set -euo pipefail

# Symlink the current dist/desktop release DMG and SLATE.app to ~/Desktop.
# Run after ./scripts/package-desktop-dmg.sh (artifacts are gitignored).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
APP_NAME="${SLATE_DESKTOP_APP_NAME:-SLATE}"
DIST="$ROOT_DIR/dist/desktop"
APP_PATH="$DIST/$APP_NAME.app"
DMG_PATH="$DIST/$APP_NAME-$VERSION.dmg"
DESKTOP="${HOME}/Desktop"

for p in "$APP_PATH" "$DMG_PATH"; do
  if [[ ! -e "$p" ]]; then
    echo "Missing: $p" >&2
    echo "Build first: SLATE_DESKTOP_VERSION=$VERSION ./scripts/package-desktop-dmg.sh --release" >&2
    exit 1
  fi
done

ln -sf "$DMG_PATH" "$DESKTOP/$APP_NAME-$VERSION.dmg"
ln -sf "$APP_PATH" "$DESKTOP/$APP_NAME.app"

echo "Desktop symlinks:"
echo "  $DESKTOP/$APP_NAME-$VERSION.dmg -> $DMG_PATH"
echo "  $DESKTOP/$APP_NAME.app -> $APP_PATH"
