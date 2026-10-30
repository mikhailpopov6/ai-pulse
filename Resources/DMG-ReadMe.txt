AI Pulse — CPU, memory and Claude/Codex limits on your Mac

INSTALL
1. Drag "AI Pulse" onto the "Applications" folder.
2. Open AI Pulse from Applications. It lives in the menu bar (no Dock icon).

FIRST LAUNCH: "Apple could not verify AI Pulse…"
AI Pulse is open source and not notarized by Apple, so macOS asks once:
- Open System Settings → Privacy & Security, scroll down and click "Open Anyway".
- Or run in Terminal:  xattr -dr com.apple.quarantine "/Applications/AI Pulse.app"

AFTER THAT
- AI Pulse adds itself to Login Items, so it starts with your Mac (toggle "Open at login" in its menu).
- Codex limits appear automatically if the Codex CLI is installed and signed in with ChatGPT.
- Claude limits: click "Sign in to Claude" in the AI Pulse menu.

Source, docs and uninstall: https://github.com/mikhailpopov6/ai-pulse
