#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
BUILD_DIR="${TMPDIR:-/tmp}/codex-meter-build"
CACHE_DIR="${TMPDIR:-/tmp}/codex-meter-cache"
mkdir -p "$BUILD_DIR" "$CACHE_DIR"
swiftc -swift-version 5 -parse-as-library -O -module-cache-path "$CACHE_DIR/modules" \
    -o "$BUILD_DIR/CodexMeter" Sources/CodexMeter/*.swift
APP_DIR="${CODEX_METER_APP_OUTPUT:-$PROJECT_DIR/dist/Codex Meter.app}"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/CodexMeter" "$APP_DIR/Contents/MacOS/CodexMeter"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
ICONSET="$BUILD_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
swift -module-cache-path "$CACHE_DIR/icon-modules" "$PROJECT_DIR/scripts/make-icon.swift" "$BUILD_DIR/AppIcon.png"
for pixels in 16 32 128 256 512; do
    sips -z "$pixels" "$pixels" "$BUILD_DIR/AppIcon.png" --out "$ICONSET/icon_${pixels}x${pixels}.png" >/dev/null
    retina=$((pixels * 2))
    sips -z "$retina" "$retina" "$BUILD_DIR/AppIcon.png" --out "$ICONSET/icon_${pixels}x${pixels}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
xattr -cr "$APP_DIR"
codesign --force --sign - "$APP_DIR"
print "Built: $APP_DIR"
