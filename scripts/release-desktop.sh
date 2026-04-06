#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_SCRIPT="$ROOT_DIR/scripts/package-desktop-dmg.sh"
NOTARIZE_SCRIPT="$ROOT_DIR/scripts/notarize-desktop-app.sh"
FEED_SCRIPT="$ROOT_DIR/scripts/generate-desktop-update-feed.sh"
VERSION_FILE="$ROOT_DIR/VERSION"

APP_NAME="${SLATE_DESKTOP_APP_NAME:-SLATE}"
OUTPUT_DIR="${SLATE_DESKTOP_OUTPUT_DIR:-$ROOT_DIR/dist/desktop}"
FEED_PATH="${SLATE_DESKTOP_UPDATE_FEED_PATH:-$OUTPUT_DIR/appcast.json}"
VERSION="${SLATE_DESKTOP_VERSION:-}"
BUILD_NUMBER="${SLATE_DESKTOP_BUILD_NUMBER:-}"
SIGN_IDENTITY="${SLATE_DESKTOP_CODESIGN_IDENTITY:-}"
DOWNLOAD_URL="${SLATE_DESKTOP_DOWNLOAD_URL:-}"
RELEASE_NOTES_URL="${SLATE_DESKTOP_RELEASE_NOTES_URL:-}"
PUBLISH_DIR="${SLATE_DESKTOP_PUBLISH_DIR:-}"
PUBLISH_URL_BASE="${SLATE_DESKTOP_PUBLISH_URL_BASE:-}"
CLEAN_BUILD="${SLATE_DESKTOP_CLEAN_BUILD:-0}"

KEYCHAIN_PROFILE="${SLATE_NOTARY_KEYCHAIN_PROFILE:-}"
APPLE_ID="${SLATE_NOTARY_APPLE_ID:-}"
APPLE_TEAM_ID="${SLATE_NOTARY_TEAM_ID:-}"
APPLE_PASSWORD="${SLATE_NOTARY_APP_PASSWORD:-}"

usage() {
  cat <<'EOF'
Usage: ./scripts/release-desktop.sh [options]

Options:
  --version <semver>              Release version (default: read from VERSION file)
  --build-number <number>         Build number override
  --sign-identity <name>          Developer ID Application identity name (required)
  --download-url <url>            Public DMG URL for update feed
  --release-notes-url <url>       Public release notes URL for update feed
  --feed-path <path>              Output feed path (default: dist/desktop/appcast.json)
  --publish-dir <path>            Copy DMG + appcast.json into this directory
  --publish-url-base <url>        Base URL used to derive --download-url if omitted
  --clean                         Clean desktop build output before build
  -h, --help                      Show this help

Notarization auth must be configured via either:
  - SLATE_NOTARY_KEYCHAIN_PROFILE
  - or all of SLATE_NOTARY_APPLE_ID, SLATE_NOTARY_TEAM_ID, SLATE_NOTARY_APP_PASSWORD
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --build-number)
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --sign-identity)
      SIGN_IDENTITY="$2"
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
    --feed-path)
      FEED_PATH="$2"
      shift 2
      ;;
    --publish-dir)
      PUBLISH_DIR="$2"
      shift 2
      ;;
    --publish-url-base)
      PUBLISH_URL_BASE="$2"
      shift 2
      ;;
    --clean)
      CLEAN_BUILD="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  if [[ ! -f "$VERSION_FILE" ]]; then
    echo "Missing VERSION file at $VERSION_FILE" >&2
    exit 1
  fi
  VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
  echo "Missing signing identity. Set SLATE_DESKTOP_CODESIGN_IDENTITY or pass --sign-identity." >&2
  exit 1
fi

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "Ad-hoc signing ('-') is not allowed for release notarization." >&2
  exit 1
fi

if ! security find-identity -v -p codesigning | awk -F '"' '{print $2}' | grep -Fx "$SIGN_IDENTITY" >/dev/null; then
  echo "Code signing identity not found in keychain:" >&2
  echo "  $SIGN_IDENTITY" >&2
  echo "Run: security find-identity -v -p codesigning" >&2
  exit 1
fi

if [[ -z "$KEYCHAIN_PROFILE" ]]; then
  if [[ -z "$APPLE_ID" || -z "$APPLE_TEAM_ID" || -z "$APPLE_PASSWORD" ]]; then
    echo "Notarization credentials missing." >&2
    echo "Set SLATE_NOTARY_KEYCHAIN_PROFILE or all of:" >&2
    echo "  SLATE_NOTARY_APPLE_ID, SLATE_NOTARY_TEAM_ID, SLATE_NOTARY_APP_PASSWORD" >&2
    exit 1
  fi
fi

DMG_PATH="$OUTPUT_DIR/$APP_NAME-$VERSION.dmg"
APP_PATH="$OUTPUT_DIR/$APP_NAME.app"

if [[ -n "$PUBLISH_URL_BASE" && -z "$DOWNLOAD_URL" ]]; then
  DOWNLOAD_URL="${PUBLISH_URL_BASE%/}/$APP_NAME-$VERSION.dmg"
fi

PACKAGE_ARGS=(--release --version "$VERSION")
if [[ -n "$BUILD_NUMBER" ]]; then
  PACKAGE_ARGS+=(--build-number "$BUILD_NUMBER")
fi
if [[ "$CLEAN_BUILD" == "1" ]]; then
  PACKAGE_ARGS+=(--clean)
fi

echo "==> Building + signing + packaging DMG"
SLATE_DESKTOP_VERSION="$VERSION" \
SLATE_DESKTOP_CODESIGN_IDENTITY="$SIGN_IDENTITY" \
"$PACKAGE_SCRIPT" "${PACKAGE_ARGS[@]}"

echo "==> Notarizing + stapling app and DMG"
SLATE_DESKTOP_VERSION="$VERSION" \
SLATE_DESKTOP_DMG_PATH="$DMG_PATH" \
SLATE_DESKTOP_APP_PATH="$APP_PATH" \
"$NOTARIZE_SCRIPT"

echo "==> Generating update feed"
FEED_ARGS=(--dmg-path "$DMG_PATH" --feed-path "$FEED_PATH")
if [[ -n "$DOWNLOAD_URL" ]]; then
  FEED_ARGS+=(--download-url "$DOWNLOAD_URL")
fi
if [[ -n "$RELEASE_NOTES_URL" ]]; then
  FEED_ARGS+=(--release-notes-url "$RELEASE_NOTES_URL")
fi
"$FEED_SCRIPT" "${FEED_ARGS[@]}"

if [[ -n "$PUBLISH_DIR" ]]; then
  echo "==> Publishing artifacts to local directory"
  mkdir -p "$PUBLISH_DIR"
  cp -f "$DMG_PATH" "$PUBLISH_DIR/"
  cp -f "$FEED_PATH" "$PUBLISH_DIR/"
  echo "Published:"
  echo "  $PUBLISH_DIR/$(basename "$DMG_PATH")"
  echo "  $PUBLISH_DIR/$(basename "$FEED_PATH")"
fi

echo ""
echo "Release pipeline complete:"
echo "  App:  $APP_PATH"
echo "  DMG:  $DMG_PATH"
echo "  Feed: $FEED_PATH"
