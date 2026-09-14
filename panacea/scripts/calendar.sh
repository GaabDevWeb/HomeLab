#!/usr/bin/env bash
# Calendar state — fonte local partilhável (rice / navbar / futuro Bonsai).
# Uso:
#   calendar.sh list
#   calendar.sh next
#   calendar.sh day YYYY-MM-DD
#   calendar.sh month YYYY-MM
#   calendar.sh summary
#   calendar.sh create '<json>'
#   calendar.sh delete <id>
set -euo pipefail

STORE="${XDG_CONFIG_HOME:-$HOME/.config}/panacea/calendar_events.json"
mkdir -p "$(dirname "$STORE")"
[ -f "$STORE" ] || echo '{"events":[]}' > "$STORE"

python3 - "$STORE" "$@" <<'PY'
import json, os, sys, uuid, time
from datetime import datetime, date, timedelta

store = sys.argv[1]
op = sys.argv[2] if len(sys.argv) > 2 else "list"
args = sys.argv[3:]

def load():
    try:
        with open(store) as f:
            d = json.load(f)
        if not isinstance(d.get("events"), list):
            d["events"] = []
        return d
    except Exception:
        return {"events": []}

def save(d):
    tmp = store + ".tmp"
    with open(tmp, "w") as f:
        json.dump(d, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, store)

def now_local():
    return datetime.now().astimezone()

def parse_dt(ev):
    """Return (start_dt, end_dt) aware local, or None."""
    try:
        d = ev.get("date") or ""
        st = ev.get("start_time") or "00:00"
        et = ev.get("end_time") or st
        start = datetime.fromisoformat(f"{d}T{st}:00").astimezone()
        end = datetime.fromisoformat(f"{d}T{et}:00").astimezone()
        if end < start:
            end = end + timedelta(days=1)
        return start, end
    except Exception:
        return None

def normalize(ev):
    t = str(ev.get("type") or "EVENT").upper()
    if t not in ("EVENT", "DEADLINE", "TASK"):
        t = "EVENT"
    return {
        "id": ev.get("id") or str(uuid.uuid4()),
        "title": str(ev.get("title") or "").strip(),
        "date": str(ev.get("date") or ""),
        "start_time": str(ev.get("start_time") or "00:00")[:5],
        "end_time": str(ev.get("end_time") or ev.get("start_time") or "00:00")[:5],
        "description": str(ev.get("description") or ""),
        "type": t,
        "project": str(ev.get("project") or ""),
    }

def valid(ev):
    if not ev["title"] or not ev["date"]:
        return False
    try:
        date.fromisoformat(ev["date"])
        datetime.strptime(ev["start_time"], "%H:%M")
        datetime.strptime(ev["end_time"], "%H:%M")
    except Exception:
        return False
    return True

def event_state(ev, now=None):
    now = now or now_local()
    pe = parse_dt(ev)
    if not pe:
        return "INVALID"
    start, end = pe
    if now < start:
        return "UPCOMING"
    if start <= now <= end:
        return "ACTIVE"
    return "COMPLETED"

data = load()
events = [normalize(e) for e in data.get("events", [])]

if op == "list":
    print(json.dumps({"ok": True, "events": events, "tz": str(now_local().tzinfo)}))
    raise SystemExit

if op == "day":
    day = args[0] if args else now_local().date().isoformat()
    day_ev = [e for e in events if e["date"] == day]
    day_ev.sort(key=lambda e: (e["start_time"], e["title"]))
    for e in day_ev:
        e["state"] = event_state(e)
    print(json.dumps({"ok": True, "date": day, "events": day_ev}))
    raise SystemExit

if op == "month":
    ym = args[0] if args else now_local().strftime("%Y-%m")
    marks = {}
    for e in events:
        if not e["date"].startswith(ym):
            continue
        day = int(e["date"].split("-")[2])
        m = marks.setdefault(str(day), {"events": 0, "deadlines": 0, "tasks": 0})
        if e["type"] == "DEADLINE":
            m["deadlines"] += 1
        elif e["type"] == "TASK":
            m["tasks"] += 1
        else:
            m["events"] += 1
    print(json.dumps({"ok": True, "month": ym, "marks": marks}))
    raise SystemExit

if op == "next":
    now = now_local()
    upcoming = []
    for e in events:
        pe = parse_dt(e)
        if not pe:
            continue
        start, end = pe
        if end >= now:
            upcoming.append((start, e, end))
    upcoming.sort(key=lambda x: x[0])
    if not upcoming:
        print(json.dumps({"ok": True, "event": None}))
        raise SystemExit
    start, e, end = upcoming[0]
    e = dict(e)
    e["state"] = event_state(e, now)
    secs = int((start - now).total_seconds())
    e["starts_in_sec"] = max(0, secs)
    e["started"] = secs <= 0
    print(json.dumps({"ok": True, "event": e, "now": now.isoformat()}))
    raise SystemExit

if op == "summary":
    today = now_local().date().isoformat()
    day_ev = [e for e in events if e["date"] == today]
    n_ev = sum(1 for e in day_ev if e["type"] == "EVENT")
    n_dl = sum(1 for e in day_ev if e["type"] == "DEADLINE")
    n_tk = sum(1 for e in day_ev if e["type"] == "TASK")
    # next overall
    nxt = None
    now = now_local()
    best = None
    for e in events:
        pe = parse_dt(e)
        if not pe:
            continue
        start, end = pe
        if end >= now and (best is None or start < best[0]):
            best = (start, e)
    if best:
        nxt = dict(best[1])
        nxt["starts_in_sec"] = max(0, int((best[0] - now).total_seconds()))
    print(json.dumps({
        "ok": True,
        "date": today,
        "events": n_ev,
        "deadlines": n_dl,
        "tasks": n_tk,
        "total": len(day_ev),
        "next": nxt,
    }))
    raise SystemExit

if op == "create":
    raw = args[0] if args else sys.stdin.read()
    try:
        ev = normalize(json.loads(raw))
    except Exception as ex:
        print(json.dumps({"ok": False, "error": f"json:{ex}"}))
        raise SystemExit(1)
    if not valid(ev):
        print(json.dumps({"ok": False, "error": "invalid"}))
        raise SystemExit(1)
    # replace if same id
    events = [e for e in events if e["id"] != ev["id"]]
    events.append(ev)
    data["events"] = events
    save(data)
    print(json.dumps({"ok": True, "event": ev}))
    raise SystemExit

if op == "delete":
    eid = args[0] if args else ""
    before = len(events)
    events = [e for e in events if e["id"] != eid]
    data["events"] = events
    save(data)
    print(json.dumps({"ok": True, "deleted": before - len(events)}))
    raise SystemExit

print(json.dumps({"ok": False, "error": "usage"}))
sys.exit(1)
PY
