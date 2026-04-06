#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESKTOP_DIR="$ROOT_DIR/apps/desktop"

APP_NAME="${SLATE_DESKTOP_APP_NAME:-SLATE}"
EXECUTABLE_NAME="${SLATE_DESKTOP_EXECUTABLE_NAME:-slate-desktop}"
CONFIGURATION="${SLATE_DESKTOP_CONFIGURATION:-release}"
OUTPUT_DIR="${SLATE_DESKTOP_OUTPUT_DIR:-$ROOT_DIR/dist/desktop}"
BUNDLE_ID="${SLATE_DESKTOP_BUNDLE_ID:-com.mountaintop.slate}"
VERSION="${SLATE_DESKTOP_VERSION:-0.1.0}"
BUILD_NUMBER="${SLATE_DESKTOP_BUILD_NUMBER:-$(date +%Y%m%d%H%M%S)}"
ICON_PATH="${SLATE_DESKTOP_ICON_PATH:-$DESKTOP_DIR/Resources/AppIcon.icns}"
COPY_DSYM="${SLATE_DESKTOP_INCLUDE_DSYM:-1}"
SIGN_IDENTITY="${SLATE_DESKTOP_CODESIGN_IDENTITY:--}"
SKIP_SIGN="${SLATE_DESKTOP_SKIP_SIGN:-0}"
UPDATE_FEED_URL="${SLATE_DESKTOP_UPDATE_FEED_URL:-}"
SUPPORT_URL="${SLATE_DESKTOP_SUPPORT_URL:-}"
CLEAN_BUILD="${SLATE_DESKTOP_CLEAN_BUILD:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)
      CONFIGURATION="debug"
      shift
      ;;
    --release)
      CONFIGURATION="release"
      shift
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --bundle-id)
      BUNDLE_ID="$2"
      shift 2
      ;;
    --version)
      VERSION="$2"
      shift 2
      ;;
    --build-number)
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --icon)
      ICON_PATH="$2"
      shift 2
      ;;
    --sign-identity)
      SIGN_IDENTITY="$2"
      shift 2
      ;;
    --skip-sign)
      SKIP_SIGN="1"
      shift
      ;;
    --clean)
      # Removes apps/desktop/.build — required after moving the repo (fixes SwiftShims PCM path errors).
      CLEAN_BUILD="1"
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ ! -d "$DESKTOP_DIR" ]]; then
  echo "Desktop app directory not found: $DESKTOP_DIR" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

if [[ "$CLEAN_BUILD" == "1" ]]; then
  echo "Clean build: removing $DESKTOP_DIR/.build"
  rm -rf "$DESKTOP_DIR/.build"
fi

echo "Building $EXECUTABLE_NAME ($CONFIGURATION)..."
(cd "$DESKTOP_DIR" && swift build -c "$CONFIGURATION" --product "$EXECUTABLE_NAME")

BIN_PATH_RAW="$(cd "$DESKTOP_DIR" && swift build -c "$CONFIGURATION" --show-bin-path)"
if [[ "$BIN_PATH_RAW" == /* ]]; then
  BUILD_DIR="$BIN_PATH_RAW"
else
  BUILD_DIR="$DESKTOP_DIR/$BIN_PATH_RAW"
fi

EXECUTABLE_PATH="$BUILD_DIR/$EXECUTABLE_NAME"
APP_PATH="$OUTPUT_DIR/$APP_NAME.app"

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "Expected executable not found at $EXECUTABLE_PATH" >&2
  exit 1
fi

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

cp "$EXECUTABLE_PATH" "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
chmod +x "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
printf 'APPL????' > "$APP_PATH/Contents/PkgInfo"

ICON_FILE=""
if [[ -f "$ICON_PATH" ]]; then
  ICON_FILE="$(basename "$ICON_PATH")"
  cp "$ICON_PATH" "$APP_PATH/Contents/Resources/$ICON_FILE"
fi

find "$BUILD_DIR" -maxdepth 1 -type d -name '*.bundle' -print0 | while IFS= read -r -d '' bundle_path; do
  cp -R "$bundle_path" "$APP_PATH/Contents/Resources/"
done

if [[ "$COPY_DSYM" == "1" && -d "$BUILD_DIR/$EXECUTABLE_NAME.dSYM" ]]; then
  cp -R "$BUILD_DIR/$EXECUTABLE_NAME.dSYM" "$OUTPUT_DIR/"
fi

ICON_PLIST=""
if [[ -n "$ICON_FILE" ]]; then
  ICON_BASE="${ICON_FILE%.icns}"
  ICON_PLIST="    <key>CFBundleIconFile</key>
    <string>$ICON_BASE</string>"
fi

UPDATE_FEED_PLIST=""
if [[ -n "$UPDATE_FEED_URL" ]]; then
  UPDATE_FEED_PLIST="    <key>SLATEUpdateFeedURL</key>
    <string>$UPDATE_FEED_URL</string>"
fi

SUPPORT_URL_PLIST=""
if [[ -n "$SUPPORT_URL" ]]; then
  SUPPORT_URL_PLIST="    <key>SUPPORT_URL</key>
    <string>$SUPPORT_URL</string>"
fi

cat > "$APP_PATH/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
${ICON_PLIST}
${UPDATE_FEED_PLIST}
${SUPPORT_URL_PLIST}
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.video</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

if [[ "$SKIP_SIGN" != "1" ]]; then
  if ! command -v codesign >/dev/null 2>&1; then
    echo "codesign not found; skipping signing."
  else
    echo "Signing app bundle..."
    if [[ "$SIGN_IDENTITY" == "-" ]]; then
      codesign --force --deep --sign - "$APP_PATH"
    else
      codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_PATH"
    fi
    codesign --verify --deep --strict "$APP_PATH"
  fi
fi

echo ""
echo "Created app bundle:"
echo "  $APP_PATH"
if [[ "$COPY_DSYM" == "1" && -d "$OUTPUT_DIR/$EXECUTABLE_NAME.dSYM" ]]; then
  echo "Created dSYM:"
  echo "  $OUTPUT_DIR/$EXECUTABLE_NAME.dSYM"
fi
