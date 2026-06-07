#!/usr/bin/env bash
# update-framework.sh — привести framework-owned пути проекта к выбранной версии framework.
# Запускается в проекте (где framework подключён как git-remote "framework").
# Не коммитит — только приводит файлы к нужному состоянию.
#
# Использование:
#   ./scripts/update-framework.sh [<ref>]
#
# <ref> — тег или ветка framework (опционально).
#         По умолчанию берётся из framework.version в текущем проекте.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --------------------------------------------------------------------------
# 1. Определить ref для обновления
# --------------------------------------------------------------------------
if [ "${1:-}" != "" ]; then
  REF="$1"
elif [ -f "$ROOT/framework.version" ]; then
  REF="$(cat "$ROOT/framework.version" | tr -d '[:space:]')"
else
  echo "ERROR: Не указан ref и файл framework.version не найден." >&2
  echo "       Передайте ref первым аргументом: $0 <ref>" >&2
  exit 1
fi

if [ -z "$REF" ]; then
  echo "ERROR: framework.version пуст. Укажите тег или ветку." >&2
  exit 1
fi

echo "update-framework: ref=$REF"

# --------------------------------------------------------------------------
# 2. Проверить наличие remote "framework"
# --------------------------------------------------------------------------
if ! git -C "$ROOT" remote get-url framework > /dev/null 2>&1; then
  echo "ERROR: git remote 'framework' не настроен." >&2
  echo "       Добавьте его: git remote add framework <url>" >&2
  exit 1
fi

# --------------------------------------------------------------------------
# 3. Fetch
# --------------------------------------------------------------------------
echo "update-framework: git fetch framework --tags ..."
git -C "$ROOT" fetch framework --tags --quiet

# Проверить, что ref существует
if ! git -C "$ROOT" rev-parse "framework/$REF" > /dev/null 2>&1 && \
   ! git -C "$ROOT" rev-parse "refs/tags/$REF" > /dev/null 2>&1; then
  echo "ERROR: ref '$REF' не найден в remote 'framework' (ни как ветка, ни как тег)." >&2
  exit 1
fi

# Определить полный git-ref для checkout
if git -C "$ROOT" rev-parse "refs/tags/$REF" > /dev/null 2>&1; then
  GIT_REF="refs/tags/$REF"
else
  GIT_REF="framework/$REF"
fi

echo "update-framework: используем git ref=$GIT_REF"

# --------------------------------------------------------------------------
# 4. Прочитать framework.manifest из выбранной версии framework
# --------------------------------------------------------------------------
FW_MANIFEST_CONTENT="$(git -C "$ROOT" show "$GIT_REF:framework.manifest" 2>/dev/null || true)"

if [ -z "$FW_MANIFEST_CONTENT" ]; then
  echo "ERROR: framework.manifest не найден в $GIT_REF." >&2
  exit 1
fi

# Парсим манифест: убрать пустые строки и комментарии
parse_manifest() {
  echo "$1" | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$'
}

NEW_PATHS="$(parse_manifest "$FW_MANIFEST_CONTENT")"

# --------------------------------------------------------------------------
# 5. Прочитать старый manifest из локального файла (для выявления удалений)
# --------------------------------------------------------------------------
OLD_PATHS=""
if [ -f "$ROOT/framework.manifest" ]; then
  OLD_PATHS="$(parse_manifest "$(cat "$ROOT/framework.manifest")")"
fi

# --------------------------------------------------------------------------
# 6. Применить framework-owned файлы (checkout из framework@ref)
# --------------------------------------------------------------------------
echo "update-framework: применяю framework-owned пути..."

while IFS= read -r fw_path; do
  fw_path="$(echo "$fw_path" | tr -d '[:space:]')"
  [ -z "$fw_path" ] && continue

  if [[ "$fw_path" == */ ]]; then
    # Директория — выгрузить через git archive | tar
    local_dir="$ROOT/$fw_path"
    echo "  DIR  $fw_path"
    # Удалить старое содержимое директории
    rm -rf "$local_dir"
    mkdir -p "$local_dir"
    # Извлечь архив директории из framework ref
    git -C "$ROOT" archive "$GIT_REF" "$fw_path" | tar -x -C "$ROOT" 2>/dev/null || {
      echo "  WARN: не удалось извлечь директорию $fw_path из $GIT_REF (возможно пустая)" >&2
    }
  else
    # Файл — git checkout
    echo "  FILE $fw_path"
    mkdir -p "$ROOT/$(dirname "$fw_path")"
    git -C "$ROOT" checkout "$GIT_REF" -- "$fw_path" 2>/dev/null || {
      echo "  WARN: файл $fw_path не найден в $GIT_REF" >&2
    }
  fi
done <<< "$NEW_PATHS"

# --------------------------------------------------------------------------
# 7. Удалить framework-owned пути, которых нет в новом манифесте
# --------------------------------------------------------------------------
if [ -n "$OLD_PATHS" ]; then
  echo "update-framework: проверяю удаления..."

  while IFS= read -r old_path; do
    old_path="$(echo "$old_path" | tr -d '[:space:]')"
    [ -z "$old_path" ] && continue

    # Путь есть в новом манифесте — оставить
    if echo "$NEW_PATHS" | grep -qxF "$old_path"; then
      continue
    fi

    local_target="$ROOT/$old_path"
    if [[ "$old_path" == */ ]]; then
      # Директория
      if [ -d "$local_target" ]; then
        echo "  DEL DIR  $old_path"
        git -C "$ROOT" rm -rf "$local_target" 2>/dev/null || rm -rf "$local_target"
      fi
    else
      # Файл
      if [ -f "$local_target" ]; then
        echo "  DEL FILE $old_path"
        git -C "$ROOT" rm -f "$local_target" 2>/dev/null || rm -f "$local_target"
      fi
    fi
  done <<< "$OLD_PATHS"
fi

# --------------------------------------------------------------------------
# 8. Показать итоговые изменения (dry-run вывод)
# --------------------------------------------------------------------------
echo ""
echo "update-framework: изменения после обновления (git status):"
git -C "$ROOT" status --short

# --------------------------------------------------------------------------
# 9. Регенерировать .opencode/agents/
# --------------------------------------------------------------------------
if [ -f "$ROOT/scripts/sync-agents.sh" ]; then
  echo ""
  echo "update-framework: регенерирую .opencode/agents/ ..."
  bash "$ROOT/scripts/sync-agents.sh"
else
  echo "WARN: scripts/sync-agents.sh не найден, пропускаю регенерацию агентов" >&2
fi

# --------------------------------------------------------------------------
# 10. Хинт по локальным настройкам Claude Code
# --------------------------------------------------------------------------
# Апдейтер намеренно НЕ создаёт settings.local.json (это включило бы локальную
# политику без явного согласия). Если файла нет — подсказать, как его завести.
if [ -f "$ROOT/.claude/settings.local.json.example" ] && [ ! -f "$ROOT/.claude/settings.local.json" ]; then
  echo ""
  echo "update-framework: локальных настроек нет. Чтобы завести локальные оверрайды:"
  echo "  cp .claude/settings.local.json.example .claude/settings.local.json"
  echo "  (и убедитесь, что .claude/settings.local.json в .gitignore проекта)"
fi

echo ""
echo "update-framework: готово. Проверьте изменения и закоммитьте по §11.9."
