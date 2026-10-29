#!/bin/bash
# Сборка AI Pulse без Xcode: swiftc + ad-hoc подпись.
set -euo pipefail
cd "$(dirname "$0")"

SDK=$(xcrun --sdk macosx --show-sdk-path)
TARGET=arm64-apple-macos14.0
OUT=build
APP="$OUT/AI Pulse.app"
APPEX="$APP/Contents/PlugIns/AIPulseWidget.appex"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APPEX/Contents/MacOS"

SWIFTFLAGS=(-sdk "$SDK" -target "$TARGET" -swift-version 5 -O -whole-module-optimization)

echo "→ виджет"
swiftc "${SWIFTFLAGS[@]}" -parse-as-library -application-extension \
  -framework WidgetKit -framework SwiftUI \
  Shared/*.swift Widget/*.swift \
  -o "$APPEX/Contents/MacOS/AIPulseWidget"
cp Resources/Widget-Info.plist "$APPEX/Contents/Info.plist"

echo "→ приложение"
swiftc "${SWIFTFLAGS[@]}" \
  -framework AppKit -framework SwiftUI -framework WidgetKit \
  Shared/*.swift App/*.swift \
  -o "$APP/Contents/MacOS/AIPulse"
cp Resources/App-Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# Системный виджет macOS показывает только с подписью Apple Development.
# Нет сертификата — подписываем ad-hoc: тогда работают меню-бар и карточка на столе.
SIGN_ID="${AIPULSE_SIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null | awk '/"Apple Development/ {print $2; exit}')}"
SIGN_ID="${SIGN_ID:--}"
if [ "$SIGN_ID" = "-" ]; then
  echo "→ подпись: ad-hoc (сертификата Apple Development нет, системный виджет не появится)"
else
  echo "→ подпись: Apple Development"
fi
codesign --force --sign "$SIGN_ID" --entitlements Resources/Widget.entitlements --timestamp=none "$APPEX"
codesign --force --sign "$SIGN_ID" --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
echo "готово: $APP"
