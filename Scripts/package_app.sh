#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Purrr"
BUNDLE_ID="io.github.kaiix.purrr"
MACOS_MIN_VERSION="14.0"
CONFIGURATION="${1:-release}"
OUTPUT_DIR="$ROOT_DIR/build"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"

if [[ "${PURRR_CODESIGN_IDENTITY+x}" == "x" ]]; then
  SIGN_IDENTITY="$PURRR_CODESIGN_IDENTITY"
else
  SIGN_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | awk -F'"' '/Apple Development:/ { print $2; exit }' \
      || true
  )"
  SIGN_IDENTITY="${SIGN_IDENTITY:--}"
fi

# shellcheck source=version.env
source "$ROOT_DIR/version.env"

"$ROOT_DIR/Scripts/build_rust.sh"
SWIFT_BUILD_ARGS=(
  --package-path "$ROOT_DIR"
  --configuration "$CONFIGURATION"
  --arch arm64
)
if [[ "$CONFIGURATION" == "release" ]]; then
  SWIFT_BUILD_ARGS+=(
    -debug-info-format none
  )
fi
swift build "${SWIFT_BUILD_ARGS[@]}"

BINARY_PATH="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)/$APP_NAME"
if [[ ! -x "$BINARY_PATH" ]]; then
  echo "ERROR: Missing executable at $BINARY_PATH" >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/LICENSE" "$APP_BUNDLE/Contents/Resources/LICENSE"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$APP_BUNDLE/Contents/Resources/ThirdPartyNotices.md"
cp "$ROOT_DIR/Assets/PurrrAppIcon.icns" "$APP_BUNDLE/Contents/Resources/PurrrAppIcon.icns"
cp "$ROOT_DIR/Assets/PurrrMenuBarIcon.png" "$APP_BUNDLE/Contents/Resources/PurrrMenuBarIcon.png"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
if [[ "$CONFIGURATION" == "release" ]]; then
  strip -S "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIconFile</key><string>PurrrAppIcon</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$MARKETING_VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>$MACOS_MIN_VERSION</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>Purrr records your voice to create dictated or translated text.</string>
</dict>
</plist>
PLIST

xattr -cr "$APP_BUNDLE"
if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign \
    --force \
    --sign "$SIGN_IDENTITY" \
    --entitlements "$ROOT_DIR/Purrr.entitlements" \
    "$APP_BUNDLE"
fi

touch "$APP_BUNDLE"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$APP_BUNDLE" >/dev/null 2>&1 || true
fi

echo "Created $APP_BUNDLE"
