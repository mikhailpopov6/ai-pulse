# AGENTS.md — AI Pulse

Инструкции для AI-агентов и разработчиков. Пользовательское описание — в [README.md](README.md).

## Что это

macOS-приложение на Swift/SwiftUI без внешних зависимостей. Показывает CPU, RAM и лимиты подписок Claude (claude.ai) и Codex (ChatGPT) в меню-баре, карточкой на рабочем столе и системным виджетом WidgetKit.

## Команды

```bash
./build.sh                    # сборка в build/AI Pulse.app (swiftc, без Xcode)
./install.sh                  # сборка + ~/Applications + LaunchAgent local.aipulse + перезапуск
./uninstall.sh                # удалить всё, включая настройки и запись Keychain AI Pulse
launchctl kickstart -k gui/$(id -u)/local.aipulse   # перезапустить установленный агент
```

Превью вёрстки в PNG, без запуска приложения:

```bash
swiftc -sdk "$(xcrun --show-sdk-path)" -target arm64-apple-macos14.0 -swift-version 5 \
  Shared/*.swift tools/preview/main.swift -o build/preview/render
./build/preview/render build/preview    # small/medium/large × real/demo/docs
```

`docs/*.png` рендерятся из `Snapshot.placeholder` (вариант `docs`). Реальные данные пользователя в репозиторий не кладём.

## Устройство

| Папка | Таргет | Роль |
|---|---|---|
| `App/` | `AI Pulse.app` (LSUIElement, без песочницы) | `main.swift` — `Store` (сбор метрик, таймеры), меню-бар и поповер; `Collectors.swift` — CPU/RAM/Codex; `ClaudeFetcher.swift` — лимиты claude.ai и Keychain; `DesktopWidget.swift` — карточка на рабочем столе |
| `Widget/` | `AIPulseWidget.appex` (WidgetKit, песочница) | только читает `snapshot.json`, ничего не считает |
| `Shared/` | компилируется в оба таргета | `Model.swift` — `Snapshot` и пути; `Views.swift` — вся вёрстка (`FullPanel`, `MediumRow`, `SmallGrid`, кольца, полосы) |

Поток данных: `Store.tick()` каждые 2 с → CPU/RAM; раз в 15 с `refreshLimits()` (Codex не чаще 55 с, Claude не чаще 85 с) → `snapshot.json` в `~/Library/Application Support/AIPulse/` → `WidgetCenter.reloadAllTimelines()`. Виджет читает файл через entitlement `temporary-exception.files.home-relative-path.read-only`.

## Правила, которые нельзя ломать

**Секреты**
- Токены не попадают в логи, файлы, stdout, аргументы команд и в репозиторий. Keychain — только через `/usr/bin/security`: чтение `find-generic-password -w` в память процесса, запись через `security -i` со stdin (как делает сам Claude Code). Так macOS не спрашивает доступ к записи.
- Codex: только `codex app-server` → `account/rateLimits/read`. Не читать `~/.codex/auth.json` и не ходить в API OpenAI напрямую.
- Claude: вход в отдельном `CLAUDE_CONFIG_DIR` = `~/Library/Application Support/AIPulse/claude-login`. Запись Keychain: `Claude Code-credentials-` + первые 8 hex-символов SHA-256 от пути конфига (формула Claude Code). Основную запись `Claude Code-credentials` не трогать: у пользователя основной Claude Code может работать через API-ключ или прокси.
- Эндпоинты Claude: `GET https://api.anthropic.com/api/oauth/usage` (заголовок `anthropic-beta: oauth-2025-04-20`) и обновление токена `POST https://platform.claude.com/v1/oauth/token` с публичным client_id Claude Code. Обновлённый токен записывается обратно в ту же запись Keychain.

**Лимиты**
- `usage` отвечает 429 на частые запросы: интервал не меньше 85 с, после 429 — пауза 5 минут (`ClaudeFetcher.backoffUntil`).
- Показываем **остаток** (`LimitWindow.leftFraction`), как Codex («% left»). Цвет считается по израсходованному: от 75% жёлтый, от 90% красный (`Theme.limitTint`). Ошибку разового запроса не показываем, пока есть данные моложе 30 минут.

**Карточка на рабочем столе** (`DesktopWidget.swift`)
- Окно `NSPanel` на уровне `desktopIconWindow + 1`, `canJoinAllSpaces`, без активации.
- Место хранится в `UserDefaults` `desktop.placements`: словарь «набор экранов → (UUID дисплея, отступ от его верхнего левого угла)». Ключ набора — отсортированные UUID подключённых дисплеев через `+`.
- Место сохраняется **только** в `mouseUp` после собственного перетаскивания (`DraggableHostingView`). `isMovableByWindowBackground` выключен намеренно.
- Каждые 2 с `tick()` возвращает карточку на сохранённое место для текущего набора экранов.
- Не возвращать сохранение по `windowDidMove` или по «фактической позиции»: macOS сама двигает окно при подключении и отключении монитора, а `didMove` после перетаскивания приходит уже после `mouseUp`. Оба способа проверены и ломались.
- Журнал: `~/Library/Application Support/AIPulse/desktop.log`.

**WidgetKit**
- `chronod` отбрасывает расширения с ad-hoc подписью (в логе: `purging instead because we shouldn't cache it`). Перенос в `/Applications` не помогает. Нужна подпись Apple Development: `build.sh` берёт её сам из `security find-identity` или из `AIPULSE_SIGN_ID`.
- Расширение обязано быть в песочнице. Реальный домашний каталог берём через `getpwuid` (`SharedPaths.realHome`), а не `NSHomeDirectory()`.

## Как проверять изменения

- Сборка: `./build.sh` без ошибок. Вёрстка — PNG из `tools/preview`.
- Данные: `jq . ~/Library/Application\ Support/AIPulse/snapshot.json`.
- Окно карточки: `CGWindowListCopyWindowInfo` по PID процесса `AIPulse` — `layer`, `bounds`.
- Логи системы: `/usr/bin/log show --predicate 'process == "chronod"'`. Полный путь обязателен: в некоторых шеллах `log` переопределён функцией.
- Не запускать двух агентов: приложение само выходит, если уже запущен экземпляр с тем же bundle id.

## Стиль

- Swift 5 language mode, macOS 14+, arm64, только системные фреймворки.
- Комментарии и строки интерфейса — на русском. Комментарий объясняет «почему», а не пересказывает код.
- Bundle id: `local.aipulse` (приложение), `local.aipulse.widget` (виджет). Это же имя у LaunchAgent и домена `UserDefaults`.
