#!/usr/bin/env bash
# Thin Bonsai-facing API over calendar.sh (same store as the rice UI).
#   calendar_api.sh today
#   calendar_api.sh day YYYY-MM-DD
#   calendar_api.sh month YYYY-MM
#   calendar_api.sh next
#   calendar_api.sh deadlines
#   calendar_api.sh create '<json>'
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SH="$HERE/calendar.sh"
op="${1:-today}"
shift || true
case "$op" in
  today) bash "$SH" day "$(date +%F)" ;;
  day) bash "$SH" day "${1:-$(date +%F)}" ;;
  month) bash "$SH" month "${1:-$(date +%Y-%m)}" ;;
  next) bash "$SH" next ;;
  summary) bash "$SH" summary ;;
  deadlines)
    python3 - "$SH" <<'PY'
import json, subprocess, sys
from datetime import date
sh = sys.argv[1]
raw = subprocess.check_output(["bash", sh, "list"], text=True)
data = json.loads(raw)
today = date.today().isoformat()
dls = [e for e in data.get("events", []) if e.get("type") == "DEADLINE" and e.get("date", "") >= today]
dls.sort(key=lambda e: (e.get("date"), e.get("start_time")))
print(json.dumps({"ok": True, "deadlines": dls}))
PY
    ;;
  create) bash "$SH" create "$@" ;;
  update) bash "$SH" create "$@" ;;
  delete) bash "$SH" delete "$@" ;;
  *) echo '{"ok":false,"error":"usage"}'; exit 1 ;;
esac
