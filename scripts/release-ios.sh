#!/usr/bin/env bash
# iOS release helpers for apps/mobile-ios (see docs/SHIPPING_RUNBOOK.md).
#
# Usage:
#   bash scripts/release-ios.sh --simulator-only
#   SLATE_IOS_SIMULATOR_DESTINATION='platform=iOS Simulator,name=iPhone 17' bash scripts/release-ios.sh --simulator-only
#   bash scripts/release-ios.sh --archive-export   # requires code signing / provisioning for device archive
#
# Version: aligns MARKETING_VERSION with repo root VERSION unless SLATE_IOS_MARKETING_VERSION is set.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOBILE_DIR="$ROOT_DIR/apps/mobile-ios"
VERSION_FILE="$ROOT_DIR/VERSION"
MARKETING_VERSION="${SLATE_IOS_MARKETING_VERSION:-}"
if [[ -z "$MARKETING_VERSION" && -f "$VERSION_FILE" ]]; then
  MARKETING_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
fi
MARKETING_VERSION="${MARKETING_VERSION:-0.0.0}"
BUILD_NUMBER="${SLATE_IOS_BUILD_NUMBER:-$(date +%Y%m%d%H%M%S)}"
DEST="${SLATE_IOS_SIMULATOR_DESTINATION:-platform=iOS Simulator,name=iPhone 15,OS=latest}"

SIMULATOR_ONLY=0
ARCHIVE_EXPORT=0

usage() {
  cat <<'EOF'
Usage:
  bash scripts/release-ios.sh --simulator-only
  bash scripts/release-ios.sh --archive-export

Environment:
  SLATE_IOS_SIMULATOR_DESTINATION   xcodebuild -destination (default: iPhone 15 simulator)
  SLATE_IOS_MARKETING_VERSION       overrides repo VERSION for archive
  SLATE_IOS_BUILD_NUMBER            CURRENT_PROJECT_VERSION for archive (default: timestamp)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --simulator-only)
      SIMULATOR_ONLY=1
      shift
      ;;
    --archive-export)
      ARCHIVE_EXPORT=1
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

if [[ "$SIMULATOR_ONLY" -eq 0 && "$ARCHIVE_EXPORT" -eq 0 ]]; then
  echo "Specify --simulator-only (CI/local checks) or --archive-export (signed IPA)." >&2
  usage >&2
  exit 1
fi

if [[ "$SIMULATOR_ONLY" -eq 1 && "$ARCHIVE_EXPORT" -eq 1 ]]; then
  echo "Use only one of --simulator-only or --archive-export." >&2
  exit 1
fi

if [[ ! -d "$MOBILE_DIR/SLATEMobile.xcodeproj" ]]; then
  echo "Expected Xcode project under $MOBILE_DIR" >&2
  exit 1
fi

cd "$MOBILE_DIR"

if [[ "$SIMULATOR_ONLY" -eq 1 ]]; then
  echo "==> iOS Simulator build + tests (unsigned)"
  echo "    Destination: $DEST"
  xcodebuild \
    -project SLATEMobile.xcodeproj \
    -scheme SLATEMobile \
    -destination "$DEST" \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    MARKETING_VERSION="$MARKETING_VERSION" \
    build test
  echo "==> Done"
  exit 0
fi

echo "==> Archive (device) + export IPA"
OUT_BASE="$ROOT_DIR/build/ios"
mkdir -p "$OUT_BASE"

xcodebuild archive \
  -project SLATEMobile.xcodeproj \
  -scheme SLATEMobile \
  -configuration Release \
  -archivePath "$OUT_BASE/SLATEMobile.xcarchive" \
  -destination 'generic/platform=iOS' \
  MARKETING_VERSION="$MARKETING_VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

xcodebuild -exportArchive \
  -archivePath "$OUT_BASE/SLATEMobile.xcarchive" \
  -exportPath "$OUT_BASE/export" \
  -exportOptionsPlist "$MOBILE_DIR/ExportOptions-appstore.plist"

echo "==> IPA output:"
ls -la "$OUT_BASE/export/"*.ipa
echo "==> Done"
