#!/bin/bash
# Builds a release "Mac Sticky Notes.app" in ./build, sandboxed and code signed.
# Usage: Scripts/package-app.sh            (ad-hoc signature, fine for running locally)
#        SIGN_ID="Apple Development: ..." Scripts/package-app.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/build/Mac Sticky Notes.app"
VERSION="${VERSION:-0.1.0}"
BUNDLE_ID="${BUNDLE_ID:-com.jimmy-tools.macstickynotes}"
SIGN_ID="${SIGN_ID:--}"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/MacStickyNotes"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacStickyNotes"
cp -R Sources/MacStickyNotes/Localization/*.lproj "$APP/Contents/Resources/"

# App icon: Design/AppIcon.png (1024px) -> AppIcon.icns
ICONSET="$ROOT/build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Design/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z "$((size * 2))" "$((size * 2))" Design/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hant</string></array>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleExecutable</key><string>MacStickyNotes</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleName</key><string>Mac Sticky Notes</string>
    <key>CFBundleDisplayName</key><string>Mac Sticky Notes</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --options runtime --entitlements Scripts/MacStickyNotes.entitlements --sign "$SIGN_ID" "$APP"
codesign --verify --strict "$APP"
echo "Built: $APP"
