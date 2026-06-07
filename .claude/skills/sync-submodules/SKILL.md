---
name: sync-submodules
description: Sync рабочих областей после мержа PR по §11.7 CLAUDE.md. Топология и ветки читаются из PROJECT.md. Триггерится только явной командой пользователя ("подтяни обновления", "синкни после мержа", "обнови сабмодули"). Делает ff-only pull в основных ветках + bump указателей в мета-репо (только для topologies=submodules). Никогда не делается автоматически.
---

# sync-submodules — Sync рабочих областей после мержа PR

Skill автоматизирует §11.7 CLAUDE.md. Используется CDO **только по явной команде пользователя** после того, как PR замержен на GitHub.

Топология проекта и список рабочих областей с основными ветками берутся из `PROJECT.md` мета-репо — единственного источника истины. Хардкода рабочих областей в этом файле нет.

## Когда применять

- Пользователь явно сказал что-то из: «подтяни обновления», «синкни после мержа», «обнови сабмодули», «sync submodules».
- **Никогда** не запускать автоматически. Даже после собственного push'а ветки — указатель в мета-репо не обновляется автоматически, потому что PR ещё не замержен.

## Процедура

### Шаг 0 — определить META_ROOT и топологию

```bash
# Найти корень проекта (по маркеру framework.manifest) и загрузить парсер
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

TOPOLOGY="$(read_topology "$PROJECT_MD")"
if [ -z "$TOPOLOGY" ]; then
  echo "FATAL: Не удалось прочитать топологию из PROJECT.md."
  exit 1
fi

ENTRIES="$(parse_workspaces "$PROJECT_MD")"
if [ -z "$ENTRIES" ]; then
  echo "FATAL: В PROJECT.md не найдено рабочих областей с основными ветками."
  exit 1
fi
```

### Шаг 1 — pre-check состояния рабочих областей

Перед sync убедиться, что в каждой рабочей области:
- Текущая ветка = основная.
- Working tree чистый.

Если нет — стоп, отчёт пользователю (это нарушение §11.6 — задача не была корректно завершена).

```bash
case "$TOPOLOGY" in
  submodules)
    echo "$ENTRIES" | while IFS=: read -r rel_path main_branch; do
      repo="$META_ROOT/$rel_path"
      label="[${rel_path%/}]"
      branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null)
      dirty=$(git -C "$repo" status --porcelain 2>/dev/null)
      if [ "$branch" != "$main_branch" ]; then
        echo "$label FAIL: ветка '$branch', ожидалась '$main_branch'. Стоп."
        exit 1
      fi
      if [ -n "$dirty" ]; then
        echo "$label FAIL: есть незакоммиченные изменения. Стоп."
        exit 1
      fi
      echo "$label OK (ветка $main_branch, tree чистый)"
    done
    ;;
  single-repo|monorepo)
    label="[$(basename "$META_ROOT")]"
    main_branch=$(echo "$ENTRIES" | head -1 | cut -d: -f2)
    if [ -z "$main_branch" ]; then
      echo "FATAL: В PROJECT.md не найдена основная ветка для $TOPOLOGY-репо."
      exit 1
    fi
    branch=$(git -C "$META_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)
    dirty=$(git -C "$META_ROOT" status --porcelain 2>/dev/null)
    if [ "$branch" != "$main_branch" ]; then
      echo "$label FAIL: ветка '$branch', ожидалась '$main_branch'. Стоп."
      exit 1
    fi
    if [ -n "$dirty" ]; then
      echo "$label FAIL: есть незакоммиченные изменения. Стоп."
      exit 1
    fi
    echo "$label OK (ветка $main_branch, tree чистый)"
    ;;
  *)
    echo "FATAL: Неизвестная топология '$TOPOLOGY' в PROJECT.md."
    exit 1
    ;;
esac
```

### Шаг 2 — ff-only pull в основных ветках

```bash
case "$TOPOLOGY" in
  submodules)
    echo "$ENTRIES" | while IFS=: read -r rel_path main_branch; do
      repo="$META_ROOT/$rel_path"
      label="[${rel_path%/}]"
      git -C "$repo" fetch origin "$main_branch"
      if ! git -C "$repo" merge --ff-only "origin/$main_branch"; then
        echo "$label FAIL: ff-merge невозможен. Стоп — не делать pull --rebase / merge --no-ff / reset --hard."
        exit 1
      fi
      echo "$label OK — обновлён до $(git -C "$repo" rev-parse --short HEAD)"
    done
    ;;
  single-repo|monorepo)
    main_branch=$(echo "$ENTRIES" | head -1 | cut -d: -f2)
    label="[$(basename "$META_ROOT")]"
    git -C "$META_ROOT" fetch origin "$main_branch"
    if ! git -C "$META_ROOT" merge --ff-only "origin/$main_branch"; then
      echo "$label FAIL: ff-merge невозможен. Стоп."
      exit 1
    fi
    echo "$label OK — обновлён до $(git -C "$META_ROOT" rev-parse --short HEAD)"
    ;;
esac
```

### Шаг 3 — выявить изменившиеся указатели (только для топологии `submodules`)

Для `single-repo` и `monorepo` этого шага нет — bump указателей рабочих областей не требуется.

```bash
if [ "$TOPOLOGY" = "submodules" ]; then
  git -C "$META_ROOT" status --short
  # Ожидаются только строки вида "M submodules/..." (изменился pointer на коммит рабочей области).
  # Если есть другие изменения — отдельно отчитаться пользователю, не мешать с bump'ом.
fi
```

### Шаг 4 — коммит bump'а в мета-репо (только для топологии `submodules`)

```bash
if [ "$TOPOLOGY" = "submodules" ]; then
  # Добавить только указатели рабочих областей
  echo "$ENTRIES" | while IFS=: read -r rel_path _; do
    git -C "$META_ROOT" add "${rel_path%/}"
  done

  # Собрать строку для commit message: "repo1, repo2 to sha1, sha2"
  BUMP_PARTS=$(echo "$ENTRIES" | while IFS=: read -r rel_path _; do
    sha=$(git -C "$META_ROOT/${rel_path%/}" rev-parse --short HEAD 2>/dev/null)
    repo=$(basename "${rel_path%/}")
    echo "$repo to $sha"
  done | paste -sd ', ')

  git -C "$META_ROOT" commit -m "chore(submodules): bump $BUMP_PARTS"
fi
```

### Шаг 5 — push мета-репо

**Только после явной команды пользователя.** Если пользователь сказал «и запушь» в той же реплике — пушим. Иначе — отчитаться и спросить.

```bash
git -C "$META_ROOT" push
```

## Запрещено в этом skill

- Запуск без явной команды пользователя.
- `pull --rebase`, `merge --no-ff`, `reset --hard`.
- Любые правки кода в рабочих областях параллельно с sync'ом.
- Изменения файлов мета-репо помимо bump'а указателей.

## Отчёт по итогам

Списком: какие рабочие области обновлены, до каких коротких SHA, есть ли push мета-репо, открытые вопросы.
