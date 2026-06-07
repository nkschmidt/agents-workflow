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

### 1. Подключить framework и вынуть бутстрап-тулинг

> `git remote add framework …` только **заводит remote** — файлы framework в репозитории ещё не появляются. Их приносит `git checkout <ref> -- <пути>` из ветки/тега framework. Минимально нужны два скрипта ниже; всё остальное `init-project.sh` подтянет сам по `framework.manifest`.

```bash
git init                                # если каталог ещё не git-репозиторий
git remote add framework git@github.com:nkschmidt/agents-workflow.git
git fetch framework --tags

# вынуть минимальный бутстрап (сам init-project + его парсер)
git checkout framework/master -- scripts/init-project.sh scripts/project-config.sh
```

### 2. Поднять каркас

```bash
./scripts/init-project.sh
```

Идемпотентно: подтянет все framework-owned файлы по манифесту (на последний тег, напр. `v0.2.0`), создаст скелет `memory/`, сидит `.claude/settings.local.json` из `.example` и добавит его в `.gitignore`, поднимет локальный OpenCode-сетап и сгенерит `.opencode/agents/`.

### 3. Подключить рабочие области

Для топологии `submodules` — добавить рабочие репозитории как субмодули (конвенция пути — `submodules/<name>`):

```bash
git submodule add git@github.com:org/backend.git submodules/backend
git submodule add git@github.com:org/infra.git   submodules/infra
git submodule update --init --recursive
```

Для `single-repo` рабочая область — сам репозиторий, шага нет. Для `monorepo` рабочие зоны уже лежат в репо. Добавить область **позже**, когда проект уже живёт, — командой Claude «добавь сабмодуль …» (скилл `add-workspace`, см. ниже).

### 4. Сгенерировать PROJECT.md

Сказать Claude «**изучи кодовую базу**» → скилл `generate-project` инспектит код всех областей и генерирует `PROJECT.md` (топология, рабочие области, ветки). Затем по апруву — `study-architecture` (онбординг агентов в архитектуру).

## Добавление рабочей области в существующий проект

Если проект уже инициализирован (`PROJECT.md` есть), а позже понадобилось подключить ещё один субмодуль (или, для `monorepo`, новую рабочую зону) — сказать Claude «**добавь сабмодуль `<url>`**» / «**подключи новый репо**». Скилл `add-workspace` оркестрирует весь цикл:

1. `git submodule add <url> <path>` (для топологии `submodules`; для `monorepo` зона уже в репо);
2. обновляет `PROJECT.md` — добавляет строку новой области (логика `generate-project`, существующие строки не затираются);
3. запускает `study-architecture` со scope **только новой области** → профильный агент пишет architecture digest в свою память.

Коммит мета-репо (подключение субмодуля + указатель) и памяти — по отдельной явной команде (§11.9 / §6 регламента). Для топологии `single-repo` скилл неприменим — рабочая область одна.

## Обновление framework в проекте

Если тулинг framework уже в проекте:

```bash
scripts/update-framework.sh           # к версии из framework.version
scripts/update-framework.sh v0.2.0    # … или к конкретному тегу
```

Приводит framework-owned пути к выбранной версии remote `framework` (**включая удаления**), затем регенерирует `.opencode/agents/`. Проектные файлы не трогаются. Изменения коммитятся по §11.9 регламента.

### Если тулинга ещё нет (или remote не подключён)

Например, проект склонировали без vendored-скриптов, либо это самый первый апдейт — `update-framework.sh` сам дочитает `framework.manifest` из выбранной версии и довыгрузит остальное:

```bash
git remote add framework git@github.com:nkschmidt/agents-workflow.git   # если remote ещё нет
git fetch framework --tags
git checkout framework/master -- scripts/update-framework.sh
scripts/update-framework.sh v0.2.0    # явный тег обязателен, если framework.version ещё нет
```

Актуальные теги: `git ls-remote --tags framework`.
