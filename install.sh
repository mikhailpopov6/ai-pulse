#!/bin/bash
# Сборка, установка в ~/Applications и автозапуск через LaunchAgent.
set -euo pipefail
cd "$(dirname "$0")"

LABEL=local.aipulse
DEST="$HOME/Applications/AI Pulse.app"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

if [ ! -f Resources/AppIcon.icns ]; then
  echo "→ иконка"
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

./build.sh

echo "→ установка"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
pkill -x AIPulse 2>/dev/null || true
rm -rf "$DEST"
mkdir -p "$HOME/Applications"
cp -R "build/AI Pulse.app" "$DEST"
"$LSREGISTER" -f "$DEST"
pluginkit -a "$DEST/Contents/PlugIns/AIPulseWidget.appex" 2>/dev/null || true

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$AGENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>$LABEL</string>
	<key>ProgramArguments</key><array><string>$DEST/Contents/MacOS/AIPulse</string></array>
	<key>RunAtLoad</key><true/>
	<key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
	<key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
EOF
launchctl bootstrap "gui/$(id -u)" "$AGENT"
echo "готово: AI Pulse запущен и будет стартовать при входе в систему"
