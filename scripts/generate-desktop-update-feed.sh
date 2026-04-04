#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${SLATE_DESKTOP_OUTPUT_DIR:-$ROOT_DIR/dist/desktop}"
APP_NAME="${SLATE_DESKTOP_APP_NAME:-SLATE}"
APP_PATH="${SLATE_DESKTOP_APP_PATH:-$OUTPUT_DIR/$APP_NAME.app}"
DMG_PATH="${SLATE_DESKTOP_DMG_PATH:-$OUTPUT_DIR/$APP_NAME-${SLATE_DESKTOP_VERSION:-0.1.0}.dmg}"
FEED_PATH="${SLATE_DESKTOP_UPDATE_FEED_PATH:-$OUTPUT_DIR/appcast.json}"
DOWNLOAD_URL="${SLATE_DESKTOP_DOWNLOAD_URL:-}"
RELEASE_NOTES_URL="${SLATE_DESKTOP_RELEASE_NOTES_URL:-}"
MINIMUM_OS_VERSION="${SLATE_DESKTOP_MINIMUM_OS_VERSION:-14.0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-path)
      APP_PATH="$2"
      shift 2
      ;;
    --dmg-path)
      DMG_PATH="$2"
      shift 2
      ;;
    --feed-path)
      FEED_PATH="$2"
      shift 2
      ;;
    --download-url)
      DOWNLOAD_URL="$2"
      shift 2
      ;;
    --release-notes-url)
      RELEASE_NOTES_URL="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found at $APP_PATH" >&2
  exit 1
fi

INFO_PLIST="$APP_PATH/Contents/Info.plist"
if [[ ! -f "$INFO_PLIST" ]]; then
  echo "Info.plist not found at $INFO_PLIST" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
PUBLISHED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

if [[ -z "$DOWNLOAD_URL" ]]; then
  if [[ -f "$DMG_PATH" ]]; then
    DOWNLOAD_URL="file://$DMG_PATH"
  else
    DOWNLOAD_URL="file://$APP_PATH"
  fi
fi

SHA_SOURCE="$APP_PATH"
if [[ -f "$DMG_PATH" ]]; then
  SHA_SOURCE="$DMG_PATH"
fi
SHA256="$(shasum -a 256 "$SHA_SOURCE" | awk '{print $1}')"

mkdir -p "$(dirname "$FEED_PATH")"

python3 - <<'PY' "$FEED_PATH" "$VERSION" "$BUILD_NUMBER" "$MINIMUM_OS_VERSION" "$DOWNLOAD_URL" "$RELEASE_NOTES_URL" "$PUBLISHED_AT" "$SHA256"
import json, pathlib, sys

path = pathlib.Path(sys.argv[1])
version, build, minimum_os, download_url, notes_url, published_at, sha256 = sys.argv[2:]
release = {
    "version": version,
    "build": build,
    "minimumOSVersion": minimum_os,
    "downloadURL": download_url,
    "releaseNotesURL": notes_url or None,
    "publishedAt": published_at,
    "sha256": sha256,
}
path.write_text(json.dumps({"releases": [release]}, indent=2) + "\n")
PY

echo "Created update feed:"
echo "  $FEED_PATH"
