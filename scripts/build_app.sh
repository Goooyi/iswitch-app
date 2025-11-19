#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="iSwitch"
BUILD_DIR="$PROJECT_ROOT/.build/release"
APP_BUNDLE="$PROJECT_ROOT/${APP_NAME}.app"

echo "==> Building $APP_NAME (release)…"
swift build -c release --package-path "$PROJECT_ROOT"

echo "==> Recreating bundle structure…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

echo "==> Copying binary and Info.plist…"
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"
cp "$PROJECT_ROOT/Sources/Resources/Info.plist" "$APP_BUNDLE/Contents/"

echo "==> Done. Launch with: open \"$APP_BUNDLE\""
