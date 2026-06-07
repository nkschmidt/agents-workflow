---
name: pre-task-check
description: Pre-task sanity check рабочих областей по §11.1 CLAUDE.md перед стартом любой задачи, требующей изменений. Топология и ветки читаются из PROJECT.md. Проверяет — текущая ветка = основная, working tree чистый, локаль up-to-date с origin. При нарушении — стоп, отчёт пользователю.
---

# pre-task-check — Pre-task sanity check рабочих областей

Skill автоматизирует §11.1 CLAUDE.md. Используется CDO **перед стартом** любой задачи, требующей изменений в рабочих областях.

Топология проекта и список рабочих областей с основными ветками берутся из `PROJECT.md` мета-репо — единственного источника истины. Хардкода рабочих областей в этом файле нет.

## Процедура

Одним Bash-вызовом:

```bash
# 1. Найти корень проекта (по маркеру framework.manifest) и загрузить парсер
PROJECT_CONFIG_SH="$(d=$(pwd); while [ "$d" != "/" ]; do \
  [ -f "$d/framework.manifest" ] && echo "$d/scripts/project-config.sh" && break; \
  d=$(dirname "$d"); done)"

if [ -z "$PROJECT_CONFIG_SH" ] || [ ! -f "$PROJECT_CONFIG_SH" ]; then
  echo "FATAL: project-config.sh не найден — framework.manifest не обнаружен в иерархии директорий."
  exit 1
fi

# shellcheck source=/dev/null
source "$PROJECT_CONFIG_SH"

META_ROOT="$(find_meta_root)"
if [ -z "$META_ROOT" ]; then
  echo "FATAL: Корень проекта не найден (маркер framework.manifest отсутствует)."
  exit 1
fi

PROJECT_MD="$META_ROOT/PROJECT.md"
if [ ! -f "$PROJECT_MD" ]; then
  echo "FATAL: PROJECT.md не найден в $META_ROOT — проект не инициализирован."
  exit 1
fi

# 2. Прочитать топологию
TOPOLOGY="$(read_topology "$PROJECT_MD")"
if [ -z "$TOPOLOGY" ]; then
  echo "FATAL: Не удалось прочитать топологию из PROJECT.md."
  exit 1
fi

# 3. Распарсить таблицу «Рабочие области»: «путь:ветка»
ENTRIES="$(parse_workspaces "$PROJECT_MD")"
if [ -z "$ENTRIES" ]; then
  echo "FATAL: В PROJECT.md не найдено рабочих областей с основными ветками."
  exit 1
fi

# 4. Выполнить check в зависимости от топологии
case "$TOPOLOGY" in
  submodules)
    echo "Топология: submodules. Проверяю субмодули..."
    echo "$ENTRIES" | while IFS=: read -r rel_path main_branch; do
      repo="$META_ROOT/$rel_path"
      label="[${rel_path%/}]"
      if [ ! -d "$repo/.git" ] && [ ! -f "$repo/.git" ]; then
        echo "$label MISSING (директория не существует или не является git-репо)"
        continue
      fi
      branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null)
      dirty=$(git -C "$repo" status --porcelain 2>/dev/null)
      git -C "$repo" fetch --quiet origin "$main_branch" 2>/dev/null
      behind=$(git -C "$repo" rev-list --count "HEAD..origin/$main_branch" 2>/dev/null)
      ahead=$(git -C "$repo" rev-list --count "origin/$main_branch..HEAD" 2>/dev/null)
      echo "$label branch=$branch (expected $main_branch) | dirty=$([ -z "$dirty" ] && echo no || echo YES) | behind=$behind | ahead=$ahead"
    done
    ;;
  single-repo|monorepo)
    label="[$(basename "$META_ROOT")]"
    main_branch=$(echo "$ENTRIES" | head -1 | cut -d: -f2)
    if [ -z "$main_branch" ]; then
      echo "FATAL: В PROJECT.md не найдена основная ветка для $TOPOLOGY-репо."
      exit 1
    fi
    echo "Топология: $TOPOLOGY. Проверяю репо..."
    branch=$(git -C "$META_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)
    dirty=$(git -C "$META_ROOT" status --porcelain 2>/dev/null)
    git -C "$META_ROOT" fetch --quiet origin "$main_branch" 2>/dev/null
    behind=$(git -C "$META_ROOT" rev-list --count "HEAD..origin/$main_branch" 2>/dev/null)
    ahead=$(git -C "$META_ROOT" rev-list --count "origin/$main_branch..HEAD" 2>/dev/null)
    echo "$label branch=$branch (expected $main_branch) | dirty=$([ -z "$dirty" ] && echo no || echo YES) | behind=$behind | ahead=$ahead"
    ;;
  *)
    echo "FATAL: Неизвестная топология '$TOPOLOGY' в PROJECT.md. Допустимые значения: submodules, single-repo, monorepo."
    exit 1
    ;;
esac
```

## Интерпретация результатов

- `branch != <основная>` → **FAIL**. Стоп, отчёт пользователю — «в `$repo` чужая ветка `$branch`, что делать?».
- `dirty=YES` → **FAIL**. Стоп, отчёт пользователю — «в `$repo` незакоммиченные изменения, что делать?».
- `behind > 0` → ветка отстала от origin. Выполнить `git merge --ff-only origin/$main`. Если ff-merge невозможен — стоп, отчёт.
- `ahead > 0` → ветка опережает origin (локальные коммиты не запушены). Стоп, отчёт пользователю.
- Все четыре пункта зелёные → можно переходить к §11.2 (создание ветки задачи).

## Запрещено в этом skill

- `git stash`, `git reset --hard`, `git checkout --` — не «тушить» проблемы автоматически.
- Переключение ветки без явной команды пользователя.
- Force-операции (`--force`, `-f`).

## После успешного check

Сообщить пользователю: «Pre-task check пройден для `<list>`. Можно создавать ветку задачи».
