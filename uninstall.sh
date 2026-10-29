#!/bin/bash
# Полное удаление AI Pulse.
LABEL=local.aipulse
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
pkill -x AIPulse 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
# запись Keychain со входом в claude.ai для отдельного конфига AI Pulse
HASH=$(printf '%s' "$HOME/Library/Application Support/AIPulse/claude-login" | shasum -a 256 | cut -c1-8)
security delete-generic-password -s "Claude Code-credentials-$HASH" >/dev/null 2>&1
defaults delete "$LABEL" >/dev/null 2>&1
rm -rf "$HOME/Applications/AI Pulse.app" "$HOME/Library/Application Support/AIPulse"
echo "AI Pulse удалён"
