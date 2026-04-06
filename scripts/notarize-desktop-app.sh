#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${SLATE_DESKTOP_OUTPUT_DIR:-$ROOT_DIR/dist/desktop}"
APP_NAME="${SLATE_DESKTOP_APP_NAME:-SLATE}"
APP_PATH="${SLATE_DESKTOP_APP_PATH:-$OUTPUT_DIR/$APP_NAME.app}"
DMG_PATH="${SLATE_DESKTOP_DMG_PATH:-$OUTPUT_DIR/$APP_NAME-${SLATE_DESKTOP_VERSION:-0.1.0}.dmg}"
KEYCHAIN_PROFILE="${SLATE_NOTARY_KEYCHAIN_PROFILE:-}"
APPLE_ID="${SLATE_NOTARY_APPLE_ID:-}"
APPLE_TEAM_ID="${SLATE_NOTARY_TEAM_ID:-}"
APPLE_PASSWORD="${SLATE_NOTARY_APP_PASSWORD:-}"

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
    --keychain-profile)
      KEYCHAIN_PROFILE="$2"
      shift 2
      ;;
    --apple-id)
      APPLE_ID="$2"
      shift 2
      ;;
    --team-id)
      APPLE_TEAM_ID="$2"
      shift 2
      ;;
    --password)
      APPLE_PASSWORD="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun not found; notarization requires Xcode Command Line Tools." >&2
  exit 1
fi

if ! xcrun notarytool --version >/dev/null 2>&1; then
  echo "xcrun notarytool is unavailable on this machine." >&2
  exit 1
fi

submit_target() {
  local target_path="$1"
  local required="${2:-0}"

  if [[ ! -e "$target_path" ]]; then
    if [[ "$required" == "1" ]]; then
      echo "Required path not found: $target_path" >&2
      exit 1
    fi
    echo "Skipping optional missing target: $target_path"
    return
  fi

  echo "Submitting for notarization:"
  echo "  $target_path"

  if [[ -n "$KEYCHAIN_PROFILE" ]]; then
    xcrun notarytool submit "$target_path" \
      --keychain-profile "$KEYCHAIN_PROFILE" \
      --wait
  else
    if [[ -z "$APPLE_ID" || -z "$APPLE_TEAM_ID" || -z "$APPLE_PASSWORD" ]]; then
      echo "Provide --keychain-profile or all of --apple-id, --team-id, and --password." >&2
      exit 1
    fi

    xcrun notarytool submit "$target_path" \
      --apple-id "$APPLE_ID" \
      --team-id "$APPLE_TEAM_ID" \
      --password "$APPLE_PASSWORD" \
      --wait
  fi

  xcrun stapler staple "$target_path"
  echo "Stapled notarization ticket:"
  echo "  $target_path"
}

submit_target "$APP_PATH" "1"
submit_target "$DMG_PATH" "0"
