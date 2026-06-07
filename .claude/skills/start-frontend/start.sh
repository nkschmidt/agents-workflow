#!/usr/bin/env bash
set -euo pipefail

# start.sh — запуск фронтенда + ngrok туннель
# Usage: start.sh <project_root> <frontend_dir> [host_header]
#
# Arguments:
#   project_root  — абсолютный путь к корню проекта (для tmp/)
#   frontend_dir  — абсолютный путь к директории фронтенда
#   host_header   — (опционально) Host заголовок для подмены через ngrok traffic policy
#
# Output (JSON на stdout при успехе):
#   {"status":"ok","url":"https://...","port":5173,"host":"app.example.internal","frontend_pid":1234,"ngrok_pid":5678}
#
# Exit codes:
#   0 — успех
#   1 — ошибка (сообщение на stderr)

PROJECT_ROOT="${1:?Usage: start.sh <project_root> <frontend_dir> [host_header]}"
FRONTEND_DIR="${2:?Usage: start.sh <project_root> <frontend_dir> [host_header]}"
HOST_HEADER="${3:-}"

TMP_DIR="$PROJECT_ROOT/.tmp"
mkdir -p "$TMP_DIR"

# --- Pre-checks ---

if ! command -v ngrok &>/dev/null; then
  echo '{"status":"error","message":"ngrok not installed. Install: brew install ngrok (macOS) or https://ngrok.com/download"}' >&2
  exit 1
fi

if ! ngrok config check &>/dev/null; then
  echo '{"status":"error","message":"ngrok not authorized. Run: ngrok config add-authtoken <token>"}' >&2
  exit 1
fi

# Check if already running
if [[ -f "$TMP_DIR/frontend.pid" ]]; then
  OLD_PID=$(cat "$TMP_DIR/frontend.pid")
  if kill -0 "$OLD_PID" 2>/dev/null; then
    echo '{"status":"error","message":"Frontend already running (PID '"$OLD_PID"'). Stop it first."}' >&2
    exit 1
  fi
fi

# --- Detect package manager ---

if [[ -f "$FRONTEND_DIR/pnpm-lock.yaml" ]]; then
  PKG_MGR="pnpm"
elif [[ -f "$FRONTEND_DIR/yarn.lock" ]]; then
  PKG_MGR="yarn"
else
  PKG_MGR="npm"
fi

# --- Detect port from vite config ---

PORT=5173  # default for Vite
if [[ -f "$FRONTEND_DIR/vite.config.ts" ]]; then
  DETECTED_PORT=$(sed -n 's/.*port:\s*\([0-9]\{1,\}\).*/\1/p' "$FRONTEND_DIR/vite.config.ts" 2>/dev/null | head -1 || true)
  if [[ -n "$DETECTED_PORT" ]]; then
    PORT="$DETECTED_PORT"
  fi
elif [[ -f "$FRONTEND_DIR/vite.config.js" ]]; then
  DETECTED_PORT=$(sed -n 's/.*port:\s*\([0-9]\{1,\}\).*/\1/p' "$FRONTEND_DIR/vite.config.js" 2>/dev/null | head -1 || true)
  if [[ -n "$DETECTED_PORT" ]]; then
    PORT="$DETECTED_PORT"
  fi
fi

# --- Start frontend ---

cd "$FRONTEND_DIR"
$PKG_MGR run dev > "$TMP_DIR/frontend.log" 2>&1 &
FRONTEND_PID=$!
echo "$FRONTEND_PID" > "$TMP_DIR/frontend.pid"

# Wait for frontend to start (check logs for up to 15 seconds)
for i in $(seq 1 15); do
  sleep 1
  if grep -qiE '(Local:|localhost:|ready|started|listening)' "$TMP_DIR/frontend.log" 2>/dev/null; then
    break
  fi
  if ! kill -0 "$FRONTEND_PID" 2>/dev/null; then
    echo '{"status":"error","message":"Frontend process died. Check '"$TMP_DIR/frontend.log"'"}' >&2
    cat "$TMP_DIR/frontend.log" >&2
    rm -f "$TMP_DIR/frontend.pid"
    exit 1
  fi
done

# Detect actual port from log (frontend may pick a different port if default is busy)
ACTUAL_PORT=$(sed -n 's/.*localhost:\([0-9]\{1,\}\).*/\1/p' "$TMP_DIR/frontend.log" | head -1)
ACTUAL_PORT="${ACTUAL_PORT:-$PORT}"
if [[ -z "$ACTUAL_PORT" ]]; then
  ACTUAL_PORT="$PORT"
fi

# --- Kill any leftover ngrok ---

pkill -f "ngrok http" 2>/dev/null || true
sleep 1

# --- Start ngrok ---

if [[ -n "$HOST_HEADER" ]]; then
  cat > "$TMP_DIR/ngrok-policy.yml" << POLICY
on_http_request:
  - actions:
      - type: remove-headers
        config:
          headers:
            - x-forwarded-host
      - type: add-headers
        config:
          headers:
            host: "$HOST_HEADER"
            x-forwarded-host: "$HOST_HEADER"
POLICY
  ngrok http "$ACTUAL_PORT" --traffic-policy-file "$TMP_DIR/ngrok-policy.yml" --log=stdout > "$TMP_DIR/ngrok.log" 2>&1 &
else
  ngrok http "$ACTUAL_PORT" --log=stdout > "$TMP_DIR/ngrok.log" 2>&1 &
fi

NGROK_PID=$!
echo "$NGROK_PID" > "$TMP_DIR/ngrok.pid"

# Wait for ngrok tunnel (up to 10 seconds)
PUBLIC_URL=""
for i in $(seq 1 10); do
  sleep 1
  # Check if ngrok died
  if ! kill -0 "$NGROK_PID" 2>/dev/null; then
    echo '{"status":"error","message":"ngrok process died. Check '"$TMP_DIR/ngrok.log"'"}' >&2
    tail -5 "$TMP_DIR/ngrok.log" >&2
    rm -f "$TMP_DIR/ngrok.pid"
    exit 1
  fi
  # Try to get URL from API
  PUBLIC_URL=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['tunnels'][0]['public_url'])" 2>/dev/null || true)
  if [[ -n "$PUBLIC_URL" ]]; then
    break
  fi
done

if [[ -z "$PUBLIC_URL" ]]; then
  echo '{"status":"error","message":"Failed to get ngrok URL after 10s. Check '"$TMP_DIR/ngrok.log"'"}' >&2
  exit 1
fi

# --- Output result ---

HOST_JSON=""
if [[ -n "$HOST_HEADER" ]]; then
  HOST_JSON=',"host":"'"$HOST_HEADER"'"'
fi

echo '{"status":"ok","url":"'"$PUBLIC_URL"'","port":'"$ACTUAL_PORT"',"frontend_pid":'"$FRONTEND_PID"',"ngrok_pid":'"$NGROK_PID"$HOST_JSON'}'
