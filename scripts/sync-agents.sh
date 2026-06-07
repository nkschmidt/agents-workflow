#!/usr/bin/env bash
# sync-agents.sh — генерация .opencode/agents/*.md из .claude/agents/*.md.
# Источник истины: .claude/agents/*.md (claude-формат с frontmatter description + тело).
# Выход: .opencode/agents/*.md с шапкой description + mode: subagent + тело агента.
# Идемпотентен: повторный запуск перезаписывает файлы в DST.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/.claude/agents"
DST="$ROOT/.opencode/agents"

if [ ! -d "$SRC" ]; then
  echo "ERROR: Директория агентов не найдена: $SRC" >&2
  exit 1
fi

mkdir -p "$DST"

# Очистить существующие файлы агентов в DST
rm -f "$DST"/*.md

generated=0

for src_file in "$SRC"/*.md; do
  [ -f "$src_file" ] || continue

  name="$(basename "$src_file")"

  # Извлечь поле description из первого frontmatter-блока (между первыми двумя ---)
  description="$(awk '
    /^---$/ { n++; next }
    n == 0 { next }
    n == 1 && /^description:/ {
      sub(/^description:[[:space:]]*/, "")
      print
      exit
    }
    n >= 2 { exit }
  ' "$src_file")"

  if [ -z "$description" ]; then
    echo "WARN: поле description не найдено в $src_file, пропускаю" >&2
    continue
  fi

  # Извлечь тело агента — всё после второго ---
  body="$(awk '
    BEGIN { n=0 }
    /^---$/ { n++; next }
    n >= 2 { print }
  ' "$src_file")"

  # Записать результирующий файл
  # Используем printf чтобы избежать проблем с heredoc и специальными символами в $body
  {
    printf '%s\n' "---"
    printf 'description: %s\n' "$description"
    printf '%s\n' "mode: subagent"
    printf '%s\n' "---"
    printf '%s\n' "$body"
  } > "$DST/$name"

  generated=$((generated + 1))
done

echo "sync-agents: сгенерировано $generated файлов в $DST"
