# AI Pulse

Загрузка Mac и лимиты AI-подписок в одном месте: **CPU**, **память**, **Claude** (claude.ai Pro/Max) и **Codex** (ChatGPT). Живёт в меню-баре и карточкой на рабочем столе.

<p>
  <img src="docs/panel.png" width="340" alt="Панель AI Pulse: CPU, RAM, лимиты Claude и Codex">
  <img src="docs/rings.png" width="364" alt="Компактный вид: четыре кольца">
</p>

## Что показывает

| Метрика | Что видно | Откуда берётся |
|---|---|---|
| **CPU** | загрузка, график за последние минуты, доля system | macOS (Mach API) |
| **RAM** | занято / всего, приложения · wired · сжатая, давление памяти, swap | macOS (Mach API, sysctl) |
| **Claude** | сколько **осталось** от лимита на 5 часов и на неделю, время до сброса, план | claude.ai — тот же источник, что у `/usage` в Claude Code |
| **Codex** | сколько **осталось** от лимита (у Pro — недельный), время до сброса, план | сам Codex: `codex app-server` |

Лимиты показываются остатком, как в Codex («44% left» = «44% осталось»). Цвет предупреждает: жёлтый, когда израсходовано 75%, красный — 90%. Кольцо RAM желтеет и краснеет по давлению памяти, а не по проценту: занятая память в macOS — норма.

## Где показывает

- **Меню-бар.** Иконка с CPU и RAM, по клику — панель с полными данными.
- **Карточка на рабочем столе.** Лежит под окнами, видна на всех рабочих столах, обновляется каждые 2 секунды.
  - Три вида: **Большой** (как панель из меню-бара), **Маленький** (то же, 80%), **Кольца** (четыре кольца в ряд).
  - Переключение — в меню AI Pulse (строка «На столе») или правым кликом по карточке.
  - Перетаскивается мышью. Место запоминается **отдельно для каждого набора экранов**: с внешним монитором — одно, только на ноутбуке — другое. Подключил монитор — карточка переехала на «мониторное» место, отключил — на «ноутбучное».
- **Системный виджет macOS** (галерея «Изменить виджеты»). Код готов, но macOS показывает сторонние виджеты только с подписью Apple Development — см. [Системный виджет](#системный-виджет).

## Установка

Нужно:
- macOS 14 или новее, Mac на Apple Silicon;
- Xcode Command Line Tools (`xcode-select --install`) — полный Xcode не нужен;
- для лимитов Codex — [Codex CLI](https://github.com/openai/codex), вход через ChatGPT (`codex login`);
- для лимитов Claude — [Claude Code](https://code.claude.com/docs/en/overview) и подписка claude.ai Pro или Max.

```bash
git clone https://github.com/mikhailpopov6/ai-pulse.git
cd ai-pulse
./install.sh
```

`install.sh` рисует иконку, собирает приложение через `swiftc`, ставит его в `~/Applications/AI Pulse.app` и включает автозапуск при входе в систему. Обновление — `git pull && ./install.sh`, удаление — `./uninstall.sh`.

## Подключение лимитов

**Codex** подхватывается сам, если `codex` установлен и вы вошли через ChatGPT. AI Pulse спрашивает лимиты у самого Codex (`codex app-server`), файлы авторизации Codex не читает.

**Claude:** в меню AI Pulse нажмите **«Войти в Claude»**. Откроется Терминал с входом в claude.ai — войдите в браузере своим аккаунтом. Вход делается в **отдельной папке конфига** (`~/Library/Application Support/AIPulse/claude-login`), поэтому ваш основной Claude Code не меняется: если он работает через API-ключ или корпоративный прокси, так и останется.

То же вручную:

```bash
env -u ANTHROPIC_BASE_URL -u ANTHROPIC_AUTH_TOKEN -u ANTHROPIC_API_KEY CLAUDE_CONFIG_DIR="$HOME/Library/Application Support/AIPulse/claude-login" claude auth login --claudeai
```

## Приватность и безопасность

- **В репозитории нет ключей, токенов и личных данных.**
- Токен входа в claude.ai хранится только в связке ключей macOS (Keychain), в той же записи, куда его кладёт Claude Code: `Claude Code-credentials-<хеш папки конфига>`. AI Pulse читает и обновляет его через системный `/usr/bin/security`, держит только в памяти и никогда не пишет в файлы, логи или аргументы команд.
- Токены Codex AI Pulse не видит вообще: авторизацией занимается сам Codex.
- Куда ходит сеть: `api.anthropic.com` (лимиты Claude) и `platform.claude.com` (обновление токена Claude). Codex ходит в сеть сам. Больше никуда.
- Сам AI Pulse пишет на диск только проценты и время сброса (`snapshot.json`), журнал перемещений карточки (`desktop.log`) и скрипт входа `claude-login.command` — в нём команда входа, без секретов.

## Что и где лежит

| Что | Где |
|---|---|
| Приложение | `~/Applications/AI Pulse.app` |
| Автозапуск | `~/Library/LaunchAgents/local.aipulse.plist` |
| Снимок метрик для виджета | `~/Library/Application Support/AIPulse/snapshot.json` |
| Журнал перемещений карточки | `~/Library/Application Support/AIPulse/desktop.log` |
| Конфиг входа в claude.ai | `~/Library/Application Support/AIPulse/claude-login/` |
| Токен claude.ai | Keychain, `Claude Code-credentials-<хеш>` |
| Настройки (вид, места карточки) | `defaults read local.aipulse` |

`./uninstall.sh` удаляет всё из этой таблицы.

## Частота обновления

| Данные | Как часто |
|---|---|
| CPU, RAM | каждые 2 секунды |
| Codex | раз в минуту |
| Claude | раз в полторы минуты; если claude.ai ответит «слишком часто» (429) — пауза 5 минут |
| Кнопка «Обновить» | сразу |

## Системный виджет

Карточка на рабочем столе работает без всяких сертификатов. Чтобы AI Pulse появился ещё и в системной галерее виджетов («Изменить виджеты»), нужна подпись Apple Development: macOS (`chronod`) отбрасывает виджеты с ad-hoc подписью.

1. Поставьте Xcode, войдите в Apple ID: Xcode → Settings → Accounts. Бесплатного аккаунта хватает.
2. Там же: Manage Certificates → «+» → **Apple Development**.
3. Запустите `./install.sh`: `build.sh` сам найдёт сертификат и подпишет им приложение и виджет. Конкретный сертификат можно указать через `AIPULSE_SIGN_ID=<SHA-1 или имя>`.

## Если что-то не так

| Симптом | Что делать |
|---|---|
| Claude: «войди в claude.ai» или «вход истёк» | меню → «Войти в Claude» |
| Claude: «claude.ai просит подождать (429)» | ничего: AI Pulse сам подождёт 5 минут |
| Codex: «codex не найден» | поставьте Codex CLI в `~/.local/bin`, `/opt/homebrew/bin` или `/usr/local/bin` |
| Карточка встала не туда | перетащите её на нужное место — запомнится для текущего набора экранов. Что происходило — в `desktop.log` |
| Нет в галерее виджетов | нужна подпись Apple Development, см. выше |

## Устройство

```
App/        приложение в меню-баре: сборщики метрик, Claude/Codex, карточка на столе
Widget/     системный виджет WidgetKit (песочница, только читает snapshot.json)
Shared/     модель данных и SwiftUI-вёрстка, общие для приложения и виджета
Resources/  Info.plist и entitlements
tools/      генерация иконки и PNG-превью вёрстки
build.sh    сборка через swiftc без Xcode
install.sh  сборка + установка + автозапуск
```

Подробности для разработчиков и AI-агентов — в [AGENTS.md](AGENTS.md).
