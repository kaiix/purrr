#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS_DIR="$ROOT_DIR/Assets"
APP_ICON_SVG="$ASSETS_DIR/PurrrAppIcon.svg"
APP_ICON_PNG="$ASSETS_DIR/PurrrAppIcon.png"
APP_ICON_ICNS="$ASSETS_DIR/PurrrAppIcon.icns"
MENU_ICON_SVG="$ASSETS_DIR/PurrrMenuBarIcon.svg"
MENU_ICON_PNG="$ASSETS_DIR/PurrrMenuBarIcon.png"
ICON_WORK_DIR="$(mktemp -d)"
ICONSET_DIR="$ICON_WORK_DIR/PurrrAppIcon.iconset"

cleanup() {
  rm -rf "$ICON_WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$ASSETS_DIR" "$ICONSET_DIR"

sips -s format png "$APP_ICON_SVG" --out "$APP_ICON_PNG" >/dev/null
sips -s format png "$MENU_ICON_SVG" --out "$MENU_ICON_PNG" >/dev/null

render_icon() {
  local pixels="$1"
  local filename="$2"
  sips -z "$pixels" "$pixels" "$APP_ICON_PNG" --out "$ICONSET_DIR/$filename" >/dev/null
}

render_icon 16 icon_16x16.png
render_icon 32 icon_16x16@2x.png
render_icon 32 icon_32x32.png
render_icon 64 icon_32x32@2x.png
render_icon 128 icon_128x128.png
render_icon 256 icon_128x128@2x.png
render_icon 256 icon_256x256.png
render_icon 512 icon_256x256@2x.png
render_icon 512 icon_512x512.png
render_icon 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET_DIR" -o "$APP_ICON_ICNS"

echo "Created $APP_ICON_PNG"
echo "Created $APP_ICON_ICNS"
echo "Created $MENU_ICON_PNG"
