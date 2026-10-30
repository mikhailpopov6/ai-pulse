#!/bin/bash
# Builds AI Pulse from source, installs it to ~/Applications and launches it.
# On first launch the app turns on "Open at login" itself (System Settings → General → Login Items).
set -euo pipefail
cd "$(dirname "$0")"

DEST="$HOME/Applications/AI Pulse.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

./build.sh

echo "→ install"
# Older builds were started by a KeepAlive LaunchAgent; unload it so it doesn't relaunch the old app.
launchctl bootout "gui/$(id -u)/local.aipulse" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/local.aipulse.plist"
pkill -x AIPulse 2>/dev/null || true
sleep 1
rm -rf "$DEST"
mkdir -p "$HOME/Applications"
cp -R "build/AI Pulse.app" "$DEST"
"$LSREGISTER" -f "$DEST"
open "$DEST"
echo "done: AI Pulse is running from $DEST"
