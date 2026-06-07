#!/usr/bin/env bash
set -euo pipefail

# diff.sh — генерация PNG-картинок из незакоммиченных изменений через silicon
# Usage: diff.sh <project_root> [target_dir]
#
# Arguments:
#   project_root — абсолютный путь к корню проекта (для tmp/)
#   target_dir   — (опционально) директория, где запускать git diff. По умолчанию = project_root
#
# Output (JSON на stdout):
#   {"status":"ok","diff":"<path>","untracked":"<path>"}
#   Значения "none" если соответствующих изменений нет.
#   {"status":"clean"} — нет незакоммиченных изменений.
#   {"status":"error","message":"..."} — ошибка.
#
# Exit codes:
#   0 — успех (включая "clean")
#   1 — ошибка

PROJECT_ROOT="${1:?Usage: diff.sh <project_root> [target_dir]}"
TARGET_DIR="${2:-$PROJECT_ROOT}"

TMP_DIR="$PROJECT_ROOT/.tmp"
mkdir -p "$TMP_DIR"

# --- Install silicon if needed ---

install_silicon() {
  local os
  os=$(uname -s)
  case "$os" in
    Darwin)
      if command -v brew &>/dev/null; then
        echo "Installing silicon via brew..." >&2
        brew install silicon >&2
      else
        echo '{"status":"error","message":"silicon not found. Install Homebrew first, then: brew install silicon"}'
        exit 1
      fi
      ;;
    Linux)
      if command -v cargo &>/dev/null; then
        echo "Installing silicon via cargo..." >&2
        cargo install silicon >&2
      else
        echo '{"status":"error","message":"silicon not found. Install Rust/cargo first, then: cargo install silicon"}'
        exit 1
      fi
      ;;
    *)
      echo '{"status":"error","message":"Unsupported OS: '"$os"'. Install silicon manually."}'
      exit 1
      ;;
  esac
}

if ! command -v silicon &>/dev/null; then
  install_silicon
  if ! command -v silicon &>/dev/null; then
    echo '{"status":"error","message":"Failed to install silicon"}'
    exit 1
  fi
fi

# --- Pre-check ---

cd "$TARGET_DIR"

if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  echo '{"status":"error","message":"Not a git repository: '"$TARGET_DIR"'"}'
  exit 1
fi

STATUS=$(git status --short)
if [[ -z "$STATUS" ]]; then
  echo '{"status":"clean"}'
  exit 0
fi

# --- Generate diff image ---

DIFF_PATH="none"
DIFF_CONTENT=$(git diff HEAD --no-color 2>/dev/null || true)

if [[ -n "$DIFF_CONTENT" ]]; then
  echo "$DIFF_CONTENT" > "$TMP_DIR/git_diff.diff"
  silicon "$TMP_DIR/git_diff.diff" --language "Diff" --theme "GitHub" -o "$TMP_DIR/diff.png" 2>/dev/null
  DIFF_PATH="$TMP_DIR/diff.png"
fi

# --- Generate untracked image ---

UNTRACKED_PATH="none"
UNTRACKED_FILES=$(git ls-files --others --exclude-standard | grep -v -E '\.(png|jpg|jpeg|gif|bmp|ico|woff2?|ttf|eot|pdf|zip|tar|gz)$' || true)

if [[ -n "$UNTRACKED_FILES" ]]; then
  echo "$UNTRACKED_FILES" | xargs -I% sh -c 'echo "=== % ==="; cat "%" 2>/dev/null; echo ""' > "$TMP_DIR/untracked.txt"
  if [[ -s "$TMP_DIR/untracked.txt" ]]; then
    silicon "$TMP_DIR/untracked.txt" --language "Markdown" --theme "GitHub" -o "$TMP_DIR/untracked.png" 2>/dev/null
    UNTRACKED_PATH="$TMP_DIR/untracked.png"
  fi
fi

# --- Compress images (keep readable, reduce file size for Telegram) ---

compress_png() {
  local src="$1"
  local max_width=2000

  if [[ ! -f "$src" ]]; then return; fi

  local width
  if command -v sips &>/dev/null; then
    width=$(sips -g pixelWidth "$src" 2>/dev/null | awk '/pixelWidth/{print $2}')
    if [[ -n "$width" && "$width" -gt "$max_width" ]]; then
      sips --resampleWidth "$max_width" "$src" --out "$src" &>/dev/null
    fi
  elif command -v ffmpeg &>/dev/null; then
    width=$(ffmpeg -i "$src" 2>&1 | sed -n 's/.* \([0-9]\{3,5\}\)x[0-9]\{3,5\}.*/\1/p' | head -1)
    if [[ -n "$width" && "$width" -gt "$max_width" ]]; then
      ffmpeg -y -i "$src" -vf "scale=${max_width}:-1" "${src}.tmp.png" &>/dev/null && mv "${src}.tmp.png" "$src"
    fi
  fi
}

if [[ "$DIFF_PATH" != "none" ]]; then compress_png "$DIFF_PATH"; fi
if [[ "$UNTRACKED_PATH" != "none" ]]; then compress_png "$UNTRACKED_PATH"; fi

# --- Output ---

echo '{"status":"ok","diff":"'"$DIFF_PATH"'","untracked":"'"$UNTRACKED_PATH"'"}'
