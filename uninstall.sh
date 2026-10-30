#!/bin/bash
# Removes AI Pulse completely: the app, its settings, data folder and its own claude.ai Keychain item.
LABEL=local.aipulse
pkill -x AIPulse 2>/dev/null
# Remove the Login Item while the app still exists (it unregisters itself and exits)
for app in "/Applications/AI Pulse.app" "$HOME/Applications/AI Pulse.app"; do
  [ -x "$app/Contents/MacOS/AIPulse" ] && "$app/Contents/MacOS/AIPulse" --uninstall
done
# LaunchAgent left by older builds
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
# Keychain item with the claude.ai sign-in made for AI Pulse's separate Claude Code config
HASH=$(printf '%s' "$HOME/Library/Application Support/AIPulse/claude-login" | shasum -a 256 | cut -c1-8)
security delete-generic-password -s "Claude Code-credentials-$HASH" >/dev/null 2>&1
defaults delete "$LABEL" >/dev/null 2>&1
rm -rf "$HOME/Applications/AI Pulse.app" "$HOME/Library/Application Support/AIPulse"
rm -rf "/Applications/AI Pulse.app" 2>/dev/null
echo "AI Pulse removed"
