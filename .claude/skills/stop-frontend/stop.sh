#!/usr/bin/env bash
set -euo pipefail

# stop.sh — остановка фронтенда и ngrok
# Usage: stop.sh <project_root>
#
# Output (JSON на stdout):
#   {"status":"ok","frontend":"stopped","ngrok":"stopped"}
#
# Exit codes:
#   0 — всегда (best-effort остановка)

PROJECT_ROOT="${1:?Usage: stop.sh <project_root>}"
TMP_DIR="$PROJECT_ROOT/.tmp"

FRONTEND_STATUS="not_found"
NGROK_STATUS="not_found"

# --- Stop frontend by PID file ---

if [[ -f "$TMP_DIR/frontend.pid" ]]; then
  PID=$(cat "$TMP_DIR/frontend.pid")
  if kill "$PID" 2>/dev/null; then
    FRONTEND_STATUS="stopped"
  fi
  rm -f "$TMP_DIR/frontend.pid"
fi

# --- Stop ngrok by PID file ---

if [[ -f "$TMP_DIR/ngrok.pid" ]]; then
  PID=$(cat "$TMP_DIR/ngrok.pid")
  if kill "$PID" 2>/dev/null; then
    NGROK_STATUS="stopped"
  fi
  rm -f "$TMP_DIR/ngrok.pid"
fi

# --- Fallback: kill by process name ---

if [[ "$FRONTEND_STATUS" == "not_found" ]]; then
  if pkill -f "react-router dev" 2>/dev/null || pkill -f "next dev" 2>/dev/null || pkill -f "vite" 2>/dev/null; then
    FRONTEND_STATUS="stopped_by_name"
  fi
fi

if [[ "$NGROK_STATUS" == "not_found" ]]; then
  if pkill -f "ngrok http" 2>/dev/null; then
    NGROK_STATUS="stopped_by_name"
  fi
fi

echo '{"status":"ok","frontend":"'"$FRONTEND_STATUS"'","ngrok":"'"$NGROK_STATUS"'"}'
