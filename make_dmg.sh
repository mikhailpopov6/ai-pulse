#!/bin/bash
# Builds a drag-to-install disk image: dist/AI-Pulse.dmg (the volume name carries the version).
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/App-Info.plist)
# Stable file name: the README links to releases/latest/download/AI-Pulse.dmg
DMG="dist/AI-Pulse.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R "build/AI Pulse.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp Resources/DMG-ReadMe.txt "$STAGE/Read Me First.txt"

mkdir -p dist
rm -f "$DMG"
echo "→ dmg"
hdiutil create -quiet -volname "AI Pulse $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
echo "done: $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
