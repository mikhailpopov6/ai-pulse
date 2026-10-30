# AGENTS.md — AI Pulse

Guide for AI agents and developers. The user-facing description is in [README.md](README.md).

## What this is

A macOS app in Swift/SwiftUI with no third-party dependencies. It shows CPU, RAM and the subscription limits of Claude (claude.ai) and Codex (ChatGPT) in the menu bar, as a desktop card, and as a WidgetKit widget.

## Commands

```bash
./build.sh        # build/AI Pulse.app (swiftc, no Xcode); generates the icon if missing
./install.sh      # build + install to ~/Applications + launch (app registers its own Login Item)
./make_dmg.sh     # build + dist/AI-Pulse.dmg (app, Applications link, Read Me First.txt)
./uninstall.sh    # remove everything, including settings and AI Pulse's Keychain item
```

Layout previews as PNG, without launching the app:

```bash
swiftc -sdk "$(xcrun --show-sdk-path)" -target arm64-apple-macos14.0 -swift-version 5 \
  Shared/*.swift tools/preview/main.swift -o build/preview/render
AIPULSE_LANG=en ./build/preview/render build/preview   # small/medium/large × real/demo/docs
```

`docs/*.png` are rendered from `Snapshot.placeholder` (the `docs` variant) in English. Never commit the user's real data.

## Releasing

1. Bump `CFBundleShortVersionString` in both `Resources/*-Info.plist`.
2. `./make_dmg.sh`, then `gh release create vX.Y.Z dist/AI-Pulse.dmg`.
3. Keep the asset name `AI-Pulse.dmg`: the README links to `releases/latest/download/AI-Pulse.dmg`.

## Architecture

| Folder | Target | Role |
|---|---|---|
| `App/` | `AI Pulse.app` (LSUIElement, not sandboxed) | `main.swift`: `Store` (metrics, timers), menu bar, popover, `LoginItem`; `Collectors.swift`: CPU/RAM/Codex; `ClaudeFetcher.swift`: claude.ai limits and Keychain; `DesktopWidget.swift`: desktop card and `AppLog` |
| `Widget/` | `AIPulseWidget.appex` (WidgetKit, sandboxed) | only reads `snapshot.json`, computes nothing |
| `Shared/` | compiled into both targets | `Model.swift`: `Snapshot`, paths, `tr()` localization, formatting; `Views.swift`: all layouts (`FullPanel`, `MediumRow`, `SmallGrid`, rings, bars) |

Data flow: `Store.tick()` every 2 s → CPU/RAM; every 15 s `refreshLimits()` (Codex at most every 55 s, Claude at most every 85 s) → `snapshot.json` in `~/Library/Application Support/AIPulse/` → `WidgetCenter.reloadAllTimelines()`. The widget reads the file through the `temporary-exception.files.home-relative-path.read-only` entitlement.

## Rules that must not break

**Secrets**
- Tokens never go to logs, files, stdout, command-line arguments or the repository. Keychain access only through `/usr/bin/security`: read with `find-generic-password -w` into process memory, write via `security -i` over stdin (the way Claude Code does it). This way macOS doesn't prompt for item access.
- Codex: only `codex app-server` → `account/rateLimits/read`. Never read `~/.codex/auth.json` and never call OpenAI APIs directly.
- Claude: the sign-in lives in a separate `CLAUDE_CONFIG_DIR` = `~/Library/Application Support/AIPulse/claude-login`. Keychain item: `Claude Code-credentials-` + the first 8 hex chars of SHA-256 of the config path (Claude Code's formula). Never touch the default `Claude Code-credentials` item: the user's main Claude Code may run on an API key or a proxy.
- Claude endpoints: `GET https://api.anthropic.com/api/oauth/usage` (header `anthropic-beta: oauth-2025-04-20`) and token refresh `POST https://platform.claude.com/v1/oauth/token` with Claude Code's public client_id. The refreshed token is written back to the same Keychain item.

**Limits**
- `usage` answers 429 to frequent requests: keep the interval ≥ 85 s, back off 5 minutes after a 429 (`ClaudeFetcher.backoffUntil`).
- Show what's **left** (`LimitWindow.leftFraction`), like Codex ("% left"). Color is driven by usage: yellow from 75%, red from 90% (`Theme.limitTint`). A one-off error is not shown while data younger than 30 minutes exists.
- `LimitWindow` stores a language-neutral `kind` (`5h`, `week`, `week_opus`, `m<minutes>`…); titles are rendered by `WindowKind.title` in the current language.

**Localization**
- All UI strings go through `tr("English", "Русский")` (`Shared/Model.swift`). English is the default; Russian when it's the first preferred language. `AIPULSE_LANG=en|ru` forces a language. Use `Text(String)` (verbatim), not string-literal keys.

**Desktop card** (`DesktopWidget.swift`)
- `NSPanel` at `desktopIconWindow + 1`, `canJoinAllSpaces`, non-activating.
- Positions live in `UserDefaults` `desktop.placements`: a dictionary "set of displays → (display UUID, offset from that display's top-left corner)". The key is the sorted UUIDs of connected displays joined with `+`.
- A position is saved **only** on `mouseUp` after our own drag (`DraggableHostingView`). `isMovableByWindowBackground` is off on purpose.
- Every 2 s `tick()` puts the card back to the saved spot for the current set of displays.
- Don't bring back saving on `windowDidMove` or on "actual position": macOS moves the window itself when displays are connected/disconnected, and `didMove` after a drag arrives after `mouseUp`. Both approaches were tried and broke.
- Log: `~/Library/Application Support/AIPulse/aipulse.log`.

**Start at login**
- `SMAppService.mainApp` (`LoginItem` in `main.swift`), turned on once on first launch, then the user's choice is kept. Older builds used a LaunchAgent `local.aipulse`; the app deletes its plist, `install.sh` also unloads it.

**WidgetKit**
- `chronod` drops ad-hoc signed extensions (log: `purging instead because we shouldn't cache it`). Moving the app to `/Applications` doesn't help. An Apple Development signature is required: `build.sh` takes it from `security find-identity` or `AIPULSE_SIGN_ID`.
- The extension must be sandboxed. Get the real home folder via `getpwuid` (`SharedPaths.realHome`), not `NSHomeDirectory()`.

## Verifying changes

- Build: `./build.sh` with no errors. Layout: PNGs from `tools/preview` in both languages.
- Data: `jq . ~/Library/Application\ Support/AIPulse/snapshot.json`.
- Desktop card window: `CGWindowListCopyWindowInfo` filtered by the `AIPulse` PID — `layer`, `bounds`.
- System logs: `/usr/bin/log show --predicate 'process == "chronod"'`. Use the full path: some shells shadow `log` with a function.
- DMG: mount with `hdiutil attach -nobrowse -readonly`, check `codesign --verify --deep --strict` on the app inside.
- Only one instance runs: the app quits if another instance with the same bundle id is running.

## Style

- Swift 5 language mode, macOS 14+, arm64, system frameworks only.
- Code comments in English; explain "why", not "what".
- Bundle id: `local.aipulse` (app), `local.aipulse.widget` (widget). Same name for the `UserDefaults` domain.
