#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="iSwitch"
APP_BUNDLE="$ROOT_DIR/${APP_NAME}.app"
DIST_DIR="$ROOT_DIR/dist"
DMG_PATH="$DIST_DIR/${APP_NAME}.dmg"
STAGE_DIR="$DIST_DIR/dmg_stage"

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "Error: $APP_BUNDLE not found. Run scripts/build_app.sh first." >&2
    exit 1
fi

echo "==> Preparing dist directory…"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "==> Staging DMG contents…"
mkdir -p "$STAGE_DIR"
cp -R "$APP_BUNDLE" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

TMP_DMG="${DIST_DIR}/${APP_NAME}-temp.dmg"

echo "==> Creating DMG at $DMG_PATH"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE_DIR" \
    -ov -fs HFS+ -format UDZO \
    "$TMP_DMG" >/dev/null

mv "$TMP_DMG" "$DMG_PATH"
rm -rf "$STAGE_DIR"

echo "==> DMG created: $DMG_PATH"
