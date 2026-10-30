#!/bin/bash
# Builds AI Pulse without Xcode: swiftc + code signing. Output: build/AI Pulse.app
set -euo pipefail
cd "$(dirname "$0")"

SDK=$(xcrun --sdk macosx --show-sdk-path)
TARGET=arm64-apple-macos14.0
OUT=build
APP="$OUT/AI Pulse.app"
APPEX="$APP/Contents/PlugIns/AIPulseWidget.appex"

if [ ! -f Resources/AppIcon.icns ]; then
  echo "→ icon"
  tmp=$(mktemp -d)
  swift tools/make_icon.swift "$tmp/icon.png"
  mkdir "$tmp/AppIcon.iconset"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$tmp/icon.png" --out "$tmp/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$tmp/icon.png" --out "$tmp/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$tmp/AppIcon.iconset" -o Resources/AppIcon.icns
  rm -rf "$tmp"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APPEX/Contents/MacOS"

SWIFTFLAGS=(-sdk "$SDK" -target "$TARGET" -swift-version 5 -O -whole-module-optimization)

echo "→ widget"
swiftc "${SWIFTFLAGS[@]}" -parse-as-library -application-extension \
  -framework WidgetKit -framework SwiftUI \
  Shared/*.swift Widget/*.swift \
  -o "$APPEX/Contents/MacOS/AIPulseWidget"
cp Resources/Widget-Info.plist "$APPEX/Contents/Info.plist"

echo "→ app"
swiftc "${SWIFTFLAGS[@]}" \
  -framework AppKit -framework SwiftUI -framework WidgetKit -framework ServiceManagement \
  Shared/*.swift App/*.swift \
  -o "$APP/Contents/MacOS/AIPulse"
cp Resources/App-Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# macOS only shows the system widget when it is signed with an Apple Development identity.
# Without one we sign ad-hoc: the menu bar app and the desktop card work either way.
SIGN_ID="${AIPULSE_SIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null | awk '/"Apple Development/ {print $2; exit}')}"
SIGN_ID="${SIGN_ID:--}"
if [ "$SIGN_ID" = "-" ]; then
  echo "→ signing: ad-hoc (no Apple Development identity, the system widget won't appear)"
else
  echo "→ signing: Apple Development"
fi
codesign --force --sign "$SIGN_ID" --entitlements Resources/Widget.entitlements --timestamp=none "$APPEX"
codesign --force --sign "$SIGN_ID" --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
echo "done: $APP"
