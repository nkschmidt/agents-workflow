# agents-workflow

Переиспользуемый **рабочий процесс для AI-агентов**: регламент (`CLAUDE.md`), набор агентов, скиллы и тулинг. Конкретные проекты строятся на его основе и подтягивают свежие версии универсальной части, не ломая свою специфику.

## Что внутри

| Путь | Назначение |
|---|---|
| `CLAUDE.md` | Универсальный регламент работы Claude (роль CDO, делегирование, жизненный цикл задач). Framework-owned. |
| `.claude/agents/` | Универсальный набор агентов (роли). Источник истины; стек конкретного проекта — в его памяти. |
| `.claude/skills/` | Framework-скиллы: `pre-task-check`, `sync-submodules`, `generate-project`. |
| `scripts/` | Тулинг: `sync-agents.sh`, `project-config.sh`, `update-framework.sh`, `init-project.sh`. |
| `opencode.json` | Конфиг агентов для OpenCode (generic). |
| `memory/README.md` | Конвенция памяти проекта. |
| `framework.manifest` | Список framework-owned путей — источник истины для апдейтера. |
| `framework.version` | Версия framework. |

В framework **нет `PROJECT.md`** — он генерируется под конкретный проект (см. ниже).

## Граница владения

Апдейтер трогает **только** пути из `framework.manifest`. Всё остальное — собственность проекта (`PROJECT.md`, `README.md`, содержимое `memory/` кроме `memory/README.md`, проектные скиллы, рабочие области). Подробности — §12 `CLAUDE.md`.

## Старт нового проекта

1. Создать репозиторий проекта, подключить рабочие области (субмодули и т.п.).
2. Подключить framework: `git remote add framework <url-этого-репо>`.
3. Поднять каркас: `scripts/init-project.sh` (или просто сказать Claude «изучи кодовую базу» — скилл `generate-project` сделает это сам при необходимости).
4. Сказать Claude «**изучи кодовую базу**» → скилл `generate-project` инспектит код и генерирует `PROJECT.md`.

## Обновление framework в проекте

```bash
scripts/update-framework.sh           # привести framework-owned пути к свежей версии
```
Приводит framework-часть к версии из remote `framework` (включая удаления), затем регенерирует `.opencode/agents/`. Проектные файлы не трогаются. Изменения коммитятся по правилам §11.9 регламента.
