---
name: stop-frontend
description: Останавливает локальный фронтенд и ngrok туннель. Триггерится когда пользователь говорит "стоп фронт", "останови фронт", "выключи фронт", "закрой ngrok", "стоп сервер".
---

# stop-frontend — Остановка фронта и ngrok

## Процедура

Одна команда:

```bash
ROOT=$(git rev-parse --show-toplevel) && bash "$ROOT/.claude/skills/stop-frontend/stop.sh" "$ROOT"
```

**ВАЖНО:** запускать с `dangerouslyDisableSandbox: true` — скрипт вызывает `pkill`.

Скрипт возвращает JSON: `{"status":"ok","frontend":"stopped","ngrok":"stopped"}`.

Возможные значения для `frontend`/`ngrok`: `stopped`, `stopped_by_name`, `not_found`.

Сообщить пользователю: "🛑 Фронт и ngrok остановлены." Если `not_found` — "Процессы не найдены, уже были остановлены."
