# agents-workflow

Переиспользуемый **рабочий процесс для AI-агентов**: регламент (`CLAUDE.md`), набор агентов, скиллы и тулинг. Конкретные проекты строятся на его основе и подтягивают свежие версии универсальной части, не ломая свою специфику.

## Что внутри

| Путь | Назначение |
|---|---|
| `CLAUDE.md` | Универсальный регламент работы Claude (роль CDO, делегирование, жизненный цикл задач). Framework-owned. |
| `.claude/agents/` | Универсальный набор агентов (роли). Источник истины; стек конкретного проекта — в его памяти. |
| `.claude/skills/` | Framework-скиллы: `generate-project`, `study-architecture`, `add-workspace`, `pre-task-check`, `sync-submodules`, `diff-image`, `start-frontend`, `stop-frontend`. |
| `scripts/` | Тулинг: `sync-agents.sh`, `project-config.sh`, `update-framework.sh`, `init-project.sh`. |
| `opencode.json` | Конфиг агентов для OpenCode (generic). |
| `.claude/settings.json` | Framework-baseline разрешений Claude Code + хук-сверка с регламентом. Framework-owned (всегда затирается апдейтером). |
| `.claude/settings.local.json.example` | Шаблон локальных оверрайдов (агрессивные разрешения, `bypassPermissions`). `init-project.sh` сидит из него `settings.local.json` один раз; сам `settings.local.json` — локальный (gitignore), юзер правит, апдейтер не трогает. |
| `memory/README.md` | Конвенция памяти проекта. |
| `framework.manifest` | Список framework-owned путей — источник истины для апдейтера. |
| `framework.version` | Версия framework. |

В framework **нет `PROJECT.md`** — он генерируется под конкретный проект (см. ниже).

## Граница владения

Апдейтер трогает **только** пути из `framework.manifest`. Всё остальное — собственность проекта (`PROJECT.md`, `README.md`, содержимое `memory/` кроме `memory/README.md`, проектные скиллы, рабочие области). Подробности — §12 `CLAUDE.md`.

## Старт нового проекта

1. Создать репозиторий проекта, подключить рабочие области (субмодули и т.п.).
2. Подключить framework: `git remote add framework git@github.com:nkschmidt/agents-workflow.git`.
3. Поднять каркас: `scripts/init-project.sh` (или просто сказать Claude «изучи кодовую базу» — скилл `generate-project` сделает это сам при необходимости).
4. Сказать Claude «**изучи кодовую базу**» → скилл `generate-project` инспектит код и генерирует `PROJECT.md`.

## Добавление рабочей области в существующий проект

Если проект уже инициализирован (`PROJECT.md` есть), а позже понадобилось подключить ещё один субмодуль (или, для `monorepo`, новую рабочую зону) — сказать Claude «**добавь сабмодуль `<url>`**» / «**подключи новый репо**». Скилл `add-workspace` оркестрирует весь цикл:

1. `git submodule add <url> <path>` (для топологии `submodules`; для `monorepo` зона уже в репо);
2. обновляет `PROJECT.md` — добавляет строку новой области (логика `generate-project`, существующие строки не затираются);
3. запускает `study-architecture` со scope **только новой области** → профильный агент пишет architecture digest в свою память.

Коммит мета-репо (подключение субмодуля + указатель) и памяти — по отдельной явной команде (§11.9 / §6 регламента). Для топологии `single-repo` скилл неприменим — рабочая область одна.

## Обновление framework в проекте

```bash
scripts/update-framework.sh           # привести framework-owned пути к свежей версии
```
Приводит framework-часть к версии из remote `framework` (включая удаления), затем регенерирует `.opencode/agents/`. Проектные файлы не трогаются. Изменения коммитятся по правилам §11.9 регламента.
