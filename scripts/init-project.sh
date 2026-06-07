#!/usr/bin/env bash
# init-project.sh — идемпотентный bootstrap каркаса нового проекта на базе framework agents-workflow.
# Запускается в корне нового проекта (или изнутри него).
#
# Использование:
#   ./scripts/init-project.sh [<framework-remote-url>]
#
# Если <framework-remote-url> не указан — скрипт попытается найти уже настроенный
# remote "framework". Если и его нет — сообщит и выйдет с ошибкой.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --------------------------------------------------------------------------
# Загрузить общий парсер (project-config.sh соседний)
# --------------------------------------------------------------------------
PROJECT_CONFIG="$SCRIPT_DIR/project-config.sh"
if [ ! -f "$PROJECT_CONFIG" ]; then
  echo "ERROR: project-config.sh не найден рядом со скриптом: $PROJECT_CONFIG" >&2
  exit 1
fi
# shellcheck source=./project-config.sh
source "$PROJECT_CONFIG"

# --------------------------------------------------------------------------
# 1. Найти корень проекта
# --------------------------------------------------------------------------
# Сначала ищем по маркеру framework.manifest (уже инициализированный проект)
if ROOT="$(find_meta_root 2>/dev/null)"; then
  echo "init-project: корень проекта найден: $ROOT"
else
  # Свежий проект — корень там, откуда запускаемся
  # Поднимаемся до корня git-репо, если есть
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  echo "init-project: новый проект, корень: $ROOT"
fi

# --------------------------------------------------------------------------
# 2. Определить URL framework remote
# --------------------------------------------------------------------------
FW_URL="${1:-}"

if [ -z "$FW_URL" ]; then
  # Попробовать взять из уже настроенного remote
  FW_URL="$(git -C "$ROOT" remote get-url framework 2>/dev/null || true)"
fi

if [ -z "$FW_URL" ]; then
  echo "ERROR: Не указан URL framework и remote 'framework' не настроен." >&2
  echo "       Передайте URL первым аргументом: $0 <framework-url>" >&2
  echo "       Пример: $0 git@github.com:your-org/agents-workflow.git" >&2
  exit 1
fi

echo "init-project: framework URL=$FW_URL"

# --------------------------------------------------------------------------
# 3. Добавить git remote "framework" (если нет)
# --------------------------------------------------------------------------
if git -C "$ROOT" remote get-url framework > /dev/null 2>&1; then
  echo "init-project: remote 'framework' уже настроен, пропускаю"
else
  echo "init-project: добавляю remote 'framework' -> $FW_URL"
  git -C "$ROOT" remote add framework "$FW_URL"
fi

# --------------------------------------------------------------------------
# 4. Bootstrap vendor: fetch + checkout framework.manifest и framework.version
# --------------------------------------------------------------------------
echo "init-project: git fetch framework --tags ..."
git -C "$ROOT" fetch framework --tags --quiet

# Определить ref: из локального framework.version (если уже есть) или latest tag
if [ -f "$ROOT/framework.version" ]; then
  FW_REF="$(cat "$ROOT/framework.version" | tr -d '[:space:]')"
  echo "init-project: использую framework.version=$FW_REF"
else
  # Взять последний тег из remote
  FW_REF="$(git -C "$ROOT" tag --list --sort=-version:refname 'v*' | head -1 || true)"
  if [ -z "$FW_REF" ]; then
    # Фоллбэк на ветку main
    FW_REF="main"
  fi
  echo "init-project: framework.version не найден, использую ref=$FW_REF"
fi

# Определить git-ref
if git -C "$ROOT" rev-parse "refs/tags/$FW_REF" > /dev/null 2>&1; then
  GIT_REF="refs/tags/$FW_REF"
elif git -C "$ROOT" rev-parse "framework/$FW_REF" > /dev/null 2>&1; then
  GIT_REF="framework/$FW_REF"
else
  echo "ERROR: ref '$FW_REF' не найден в remote 'framework'." >&2
  exit 1
fi

echo "init-project: bootstrap из $GIT_REF"

# Сначала выгрузить framework.manifest и framework.version
# (они нужны update-framework.sh для остального)
git -C "$ROOT" checkout "$GIT_REF" -- framework.manifest framework.version

# Передать управление update-framework.sh для остальных framework-owned путей
UPDATE_SCRIPT="$ROOT/scripts/update-framework.sh"
if [ ! -f "$UPDATE_SCRIPT" ]; then
  # update-framework.sh ещё не выгружен — выгрузить вручную
  git -C "$ROOT" checkout "$GIT_REF" -- scripts/update-framework.sh
fi

# Запустить update-framework для полного vendor'а (передаём ref явно)
echo "init-project: запускаю update-framework.sh для полного vendor'а ..."
bash "$UPDATE_SCRIPT" "$FW_REF"

# --------------------------------------------------------------------------
# 5. Скелет памяти
# --------------------------------------------------------------------------
echo "init-project: создаю скелет memory/ ..."

ensure_dir() {
  [ -d "$1" ] || mkdir -p "$1"
}

ensure_file() {
  local path="$1"
  local content="$2"
  if [ ! -f "$path" ]; then
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$content" > "$path"
    echo "  CREATE $path"
  else
    echo "  SKIP   $path (уже существует)"
  fi
}

# memory/MEMORY.md (CDO-индекс)
ensure_dir "$ROOT/memory"
ensure_file "$ROOT/memory/MEMORY.md" "# Memory index"

# memory/_shared/MEMORY.md
ensure_dir "$ROOT/memory/_shared"
ensure_file "$ROOT/memory/_shared/MEMORY.md" "# Shared memory index"

# memory/<agent>/MEMORY.md для каждого агента из .claude/agents/
AGENTS_DIR="$ROOT/.claude/agents"
if [ -d "$AGENTS_DIR" ]; then
  for agent_file in "$AGENTS_DIR"/*.md; do
    [ -f "$agent_file" ] || continue
    agent_name="$(basename "$agent_file" .md)"
    ensure_dir "$ROOT/memory/$agent_name"
    ensure_file "$ROOT/memory/$agent_name/MEMORY.md" "# Memory index — $agent_name"
  done
fi

# --------------------------------------------------------------------------
# 6. Локальные настройки Claude Code (seed once, апдейтером не затирается)
# --------------------------------------------------------------------------
# settings.json — общий framework-baseline (в манифесте, всегда затирается).
# settings.local.json — локальные оверрайды юзера: создаём один раз из шаблона
# settings.local.json.example, дальше не трогаем (файл в .gitignore).
echo "init-project: настраиваю .claude/settings.local.json ..."

LOCAL_SETTINGS="$ROOT/.claude/settings.local.json"
EXAMPLE_SETTINGS="$ROOT/.claude/settings.local.json.example"
if [ -f "$LOCAL_SETTINGS" ]; then
  echo "  SKIP   $LOCAL_SETTINGS (уже существует)"
elif [ -f "$EXAMPLE_SETTINGS" ]; then
  cp "$EXAMPLE_SETTINGS" "$LOCAL_SETTINGS"
  echo "  CREATE $LOCAL_SETTINGS (из settings.local.json.example)"
else
  echo "  WARN: $EXAMPLE_SETTINGS не найден — пропускаю seed локальных настроек" >&2
fi

# Гарантировать, что локальный файл настроек игнорируется в проекте.
# Проектный .gitignore не framework-owned (нет в манифесте) → правим его здесь,
# иначе settings.local.json с bypassPermissions может случайно попасть в репо проекта.
GITIGNORE="$ROOT/.gitignore"
IGNORE_LINE=".claude/settings.local.json"
if [ ! -f "$GITIGNORE" ] || ! grep -qxF "$IGNORE_LINE" "$GITIGNORE"; then
  printf '\n# Локальные оверрайды настроек Claude Code (не коммитим)\n%s\n' "$IGNORE_LINE" >> "$GITIGNORE"
  echo "  GITIGNORE += $IGNORE_LINE"
else
  echo "  SKIP   .gitignore (правило $IGNORE_LINE уже есть)"
fi

# --------------------------------------------------------------------------
# 7. Локальный OpenCode-сетап (gitignore)
# --------------------------------------------------------------------------
echo "init-project: настраиваю .opencode/ ..."

ensure_dir "$ROOT/.opencode"

# .opencode/package.json
ensure_file "$ROOT/.opencode/package.json" \
  '{"dependencies":{"@opencode-ai/plugin":"1.15.10"}}'

# .opencode/.gitignore
ensure_file "$ROOT/.opencode/.gitignore" \
"node_modules
package.json
package-lock.json
bun.lock
.gitignore"

# Установить зависимости (bun или npm — что есть)
echo "init-project: устанавливаю OpenCode dependencies ..."
if command -v bun > /dev/null 2>&1; then
  (cd "$ROOT/.opencode" && bun install --silent)
  echo "  bun install OK"
elif command -v npm > /dev/null 2>&1; then
  (cd "$ROOT/.opencode" && npm install --silent)
  echo "  npm install OK"
else
  echo "  WARN: ни bun ни npm не найдены — установите зависимости вручную в .opencode/" >&2
fi

# --------------------------------------------------------------------------
# 8. Регенерировать .opencode/agents/
# --------------------------------------------------------------------------
echo "init-project: регенерирую .opencode/agents/ ..."
bash "$ROOT/scripts/sync-agents.sh"

# --------------------------------------------------------------------------
# Готово
# --------------------------------------------------------------------------
echo ""
echo "init-project: инициализация завершена."
echo "  Следующий шаг: скажите 'изучи кодовую базу' — скилл generate-project"
echo "  сгенерирует PROJECT.md под ваш проект."
