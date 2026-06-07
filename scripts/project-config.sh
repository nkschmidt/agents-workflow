#!/usr/bin/env bash
# project-config.sh — общий парсер PROJECT.md для framework agents-workflow.
# Предназначен для source, не для прямого запуска.
#
# Экспортирует функции:
#   find_meta_root   — найти корень проекта по маркеру framework.manifest
#   read_topology    — прочитать топологию из PROJECT.md
#   parse_workspaces — распарсить таблицу рабочих областей: "путь:ветка" на строку

# find_meta_root — подъём вверх от $PWD до каталога с framework.manifest.
# Выводит абсолютный путь корня в stdout.
# Возвращает 1, если маркер не найден.
find_meta_root() {
  local d
  d="$(pwd)"
  while [ "$d" != "/" ]; do
    if [ -f "$d/framework.manifest" ]; then
      echo "$d"
      return 0
    fi
    d="$(dirname "$d")"
  done
  return 1
}

# read_topology — читает значение топологии из секции "## Топология" в PROJECT.md.
# Аргумент $1: путь до PROJECT.md (обязателен).
# Выводит одно слово: submodules | single-repo | monorepo (или пусто, если не найдено).
read_topology() {
  local project_md="${1:-}"
  if [ -z "$project_md" ] || [ ! -f "$project_md" ]; then
    return 0
  fi
  awk '
    /^## Топология/ { found=1; next }
    found && /^`[^`]+`/ {
      gsub(/`/, "", $0)
      # убрать пробелы по краям
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
      print $0
      exit
    }
    # прекратить поиск при следующем заголовке ##
    found && /^## / { exit }
  ' "$project_md"
}

# parse_workspaces — извлечь пары "путь:ветка" из таблицы "## Рабочие области" в PROJECT.md.
# Аргумент $1: путь до PROJECT.md (обязателен).
# Формат вывода: одна пара на строку, разделитель ":".
# Путь — первый backtick-столбец таблицы; ветка — последний backtick-столбец.
# Трейлинг-слеш в пути сохраняется как есть (для совместимости с git submodule paths).
parse_workspaces() {
  local project_md="${1:-}"
  if [ -z "$project_md" ] || [ ! -f "$project_md" ]; then
    return 0
  fi
  awk '
    # Включить режим парсинга при входе в секцию "## Рабочие области"
    /^## Рабочие области/ { in_section=1; next }
    # Выйти при следующем заголовке ##
    in_section && /^## / { in_section=0; next }
    # Обрабатывать строки таблицы с backtick-значениями
    in_section && /^\|[[:space:]]*`/ {
      n = split($0, cols, "|")
      path_col = ""
      branch_col = ""
      for (i = 1; i <= n; i++) {
        val = cols[i]
        # убрать пробелы по краям
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
        # только столбцы вида `значение` (backtick с обеих сторон)
        if (val ~ /^`[^`]+`$/) {
          if (path_col == "") path_col = val
          branch_col = val
        }
      }
      # путь и ветка должны быть разными столбцами
      if (path_col != "" && branch_col != "" && path_col != branch_col) {
        gsub(/`/, "", path_col)
        gsub(/`/, "", branch_col)
        print path_col ":" branch_col
      }
    }
  ' "$project_md"
}
