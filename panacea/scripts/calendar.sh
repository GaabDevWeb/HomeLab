#!/usr/bin/env bash
# Calendar state — fonte local partilhável (rice / navbar / futuro Bonsai).
# Uso:
#   calendar.sh list
#   calendar.sh next
#   calendar.sh day YYYY-MM-DD
#   calendar.sh month YYYY-MM
#   calendar.sh summary
#   calendar.sh create '<json>'
#   calendar.sh delete <id> [occurrence|series]
#   calendar.sh due-reminders
#   calendar.sh mark-reminded '<json>'   # {id, key}
set -euo pipefail

STORE="${XDG_CONFIG_HOME:-$HOME/.config}/panacea/calendar_events.json"
mkdir -p "$(dirname "$STORE")"
[ -f "$STORE" ] || echo '{"events":[]}' > "$STORE"

python3 - "$STORE" "$@" <<'PY'
import json, os, sys, uuid
from datetime import datetime, date, timedelta

store = sys.argv[1]
op = sys.argv[2] if len(sys.argv) > 2 else "list"
args = sys.argv[3:]

REMINDERS = {"none", "at_time", "5", "10", "15", "30", "60"}
RECUR = {"never", "daily", "weekly", "monthly"}

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
    rem = str(ev.get("reminder") or "10").lower()
    if rem not in REMINDERS:
        rem = "10"
    rec = str(ev.get("recurrence") or "never").lower()
    if rec not in RECUR:
        rec = "never"
    reminded = ev.get("reminded")
    if not isinstance(reminded, dict):
        reminded = {}
    exceptions = ev.get("exceptions")
    if not isinstance(exceptions, list):
        exceptions = []
    exceptions = [str(x) for x in exceptions]
    return {
        "id": ev.get("id") or str(uuid.uuid4()),
        "title": str(ev.get("title") or "").strip(),
        "date": str(ev.get("date") or ""),
        "start_time": str(ev.get("start_time") or "00:00")[:5],
        "end_time": str(ev.get("end_time") or ev.get("start_time") or "00:00")[:5],
        "description": str(ev.get("description") or ""),
        "type": t,
        "project": str(ev.get("project") or ""),
        "reminder": rem,
        "recurrence": rec,
        "reminded": reminded,
        "exceptions": exceptions,
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

def iter_dates(master, from_d, to_d):
    """Yield occurrence dates for master within [from_d, to_d] inclusive."""
    try:
        anchor = date.fromisoformat(master["date"])
    except Exception:
        return
    rec = master.get("recurrence") or "never"
    ex = set(master.get("exceptions") or [])
    if rec == "never":
        if from_d <= anchor <= to_d and master["date"] not in ex:
            yield anchor
        return
    d = max(anchor, from_d)
    # walk back to first valid on/after from_d matching pattern
    if rec == "daily":
        cur = d
        while cur <= to_d:
            if cur >= anchor:
                iso = cur.isoformat()
                if iso not in ex:
                    yield cur
            cur += timedelta(days=1)
    elif rec == "weekly":
        # same weekday as anchor
        cur = d
        # align to weekday
        delta = (anchor.weekday() - cur.weekday()) % 7
        cur = cur + timedelta(days=delta)
        if cur < d:
            cur += timedelta(days=7)
        while cur <= to_d:
            if cur >= anchor:
                iso = cur.isoformat()
                if iso not in ex:
                    yield cur
            cur += timedelta(days=7)
    elif rec == "monthly":
        y, m = d.year, d.month
        day = anchor.day
        while True:
            try:
                cur = date(y, m, min(day, 28))
                # clamp to last day of month if needed
                import calendar as cal
                last = cal.monthrange(y, m)[1]
                cur = date(y, m, min(day, last))
            except Exception:
                break
            if cur > to_d:
                break
            if cur >= max(anchor, from_d):
                iso = cur.isoformat()
                if iso not in ex:
                    yield cur
            m += 1
            if m > 12:
                m = 1
                y += 1

def occurrence(master, occ_date):
    e = dict(master)
    e["date"] = occ_date.isoformat()
    e["series_id"] = master["id"]
    e["occurrence_id"] = f"{master['id']}@{e['date']}"
    e["is_occurrence"] = master.get("recurrence", "never") != "never"
    return e

def expand(masters, from_d, to_d):
    out = []
    for m in masters:
        for od in iter_dates(m, from_d, to_d):
            out.append(occurrence(m, od))
    out.sort(key=lambda e: (e["date"], e["start_time"], e["title"]))
    return out

def masters_by_id(events):
    return {e["id"]: e for e in events}

data = load()
# keep raw reminded/exceptions through normalize
events = [normalize(e) for e in data.get("events", [])]
# preserve reminded from file if normalize wiped incorrectly — already kept

if op == "list":
    # expanded window for UI day filter + next
    today = now_local().date()
    expanded = expand(events, today - timedelta(days=7), today + timedelta(days=90))
    print(json.dumps({
        "ok": True,
        "events": expanded,
        "masters": events,
        "tz": str(now_local().tzinfo),
    }))
    raise SystemExit

if op == "day":
    day = args[0] if args else now_local().date().isoformat()
    d0 = date.fromisoformat(day)
    day_ev = expand(events, d0, d0)
    for e in day_ev:
        e["state"] = event_state(e)
    print(json.dumps({"ok": True, "date": day, "events": day_ev}))
    raise SystemExit

if op == "month":
    ym = args[0] if args else now_local().strftime("%Y-%m")
    y, m = map(int, ym.split("-"))
    import calendar as cal
    last = cal.monthrange(y, m)[1]
    from_d = date(y, m, 1)
    to_d = date(y, m, last)
    expanded = expand(events, from_d, to_d)
    marks = {}
    for e in expanded:
        day = int(e["date"].split("-")[2])
        mk = marks.setdefault(str(day), {"events": 0, "deadlines": 0, "tasks": 0})
        if e["type"] == "DEADLINE":
            mk["deadlines"] += 1
        elif e["type"] == "TASK":
            mk["tasks"] += 1
        else:
            mk["events"] += 1
    print(json.dumps({"ok": True, "month": ym, "marks": marks}))
    raise SystemExit

if op == "next":
    now = now_local()
    today = now.date()
    expanded = expand(events, today - timedelta(days=1), today + timedelta(days=90))
    upcoming = []
    for e in expanded:
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
    today = now_local().date()
    day_ev = expand(events, today, today)
    n_ev = sum(1 for e in day_ev if e["type"] == "EVENT")
    n_dl = sum(1 for e in day_ev if e["type"] == "DEADLINE")
    n_tk = sum(1 for e in day_ev if e["type"] == "TASK")
    nxt = None
    now = now_local()
    expanded = expand(events, today - timedelta(days=1), today + timedelta(days=90))
    best = None
    for e in expanded:
        pe = parse_dt(e)
        if not pe:
            continue
        start, end = pe
        if end >= now and (best is None or start < best[0]):
            best = (start, e)
    if best:
        nxt = dict(best[1])
        nxt["starts_in_sec"] = max(0, int((best[0] - now).total_seconds()))
        nxt["started"] = nxt["starts_in_sec"] <= 0
    print(json.dumps({
        "ok": True,
        "date": today.isoformat(),
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
        incoming = json.loads(raw)
    except Exception as ex:
        print(json.dumps({"ok": False, "error": f"json:{ex}"}))
        raise SystemExit(1)
    # if editing occurrence of series without changing recurrence → update master times/title
    # UI always sends master id for edit
    ev = normalize(incoming)
    if not valid(ev):
        print(json.dumps({"ok": False, "error": "invalid"}))
        raise SystemExit(1)
    # preserve reminded if updating same id and not provided empty wipe
    old = next((e for e in events if e["id"] == ev["id"]), None)
    if old and not incoming.get("reminded") and old.get("reminded"):
        ev["reminded"] = old["reminded"]
    if old and "exceptions" not in incoming and old.get("exceptions"):
        ev["exceptions"] = old["exceptions"]
    events = [e for e in events if e["id"] != ev["id"]]
    events.append(ev)
    data["events"] = events
    save(data)
    print(json.dumps({"ok": True, "event": ev}))
    raise SystemExit

if op == "delete":
    eid = args[0] if args else ""
    mode = args[1] if len(args) > 1 else "series"
    # occurrence id form: uuid@YYYY-MM-DD
    if "@" in eid and mode == "occurrence":
        sid, od = eid.split("@", 1)
        for i, e in enumerate(events):
            if e["id"] == sid:
                ex = list(e.get("exceptions") or [])
                if od not in ex:
                    ex.append(od)
                e["exceptions"] = ex
                events[i] = e
                data["events"] = events
                save(data)
                print(json.dumps({"ok": True, "deleted": 1, "mode": "occurrence"}))
                raise SystemExit
        print(json.dumps({"ok": False, "error": "not_found"}))
        raise SystemExit(1)
    # series / plain id
    sid = eid.split("@", 1)[0]
    before = len(events)
    events = [e for e in events if e["id"] != sid]
    data["events"] = events
    save(data)
    print(json.dumps({"ok": True, "deleted": before - len(events), "mode": "series"}))
    raise SystemExit

if op == "due-reminders":
    # Return notifications that should fire now (once). Does not mutate.
    now = now_local()
    today = now.date()
    expanded = expand(events, today - timedelta(days=1), today + timedelta(days=2))
    by_master = masters_by_id(events)
    due = []
    for e in expanded:
        rem = e.get("reminder") or "none"
        if rem == "none":
            continue
        pe = parse_dt(e)
        if not pe:
            continue
        start, end = pe
        if rem == "at_time":
            fire_at = start
            key = f"{e['date']}:at_time"
            title_prefix = "NOW"
            body = f"{e['title']}\nstarting now"
            window_sec = 90
        else:
            mins = int(rem)
            fire_at = start - timedelta(minutes=mins)
            key = f"{e['date']}:{mins}"
            title_prefix = "UPCOMING"
            body = f"{e['title']}\nstarts in {mins} minutes"
            window_sec = 90
        # only fire if we're within window after fire_at and before start+2m
        delta = (now - fire_at).total_seconds()
        if delta < 0 or delta > window_sec:
            continue
        if now > end:
            continue
        master = by_master.get(e.get("series_id") or e["id"])
        reminded = (master or e).get("reminded") or {}
        if reminded.get(key):
            continue
        due.append({
            "id": e.get("series_id") or e["id"],
            "occurrence_id": e.get("occurrence_id") or e["id"],
            "key": key,
            "notify_title": title_prefix,
            "notify_body": body,
            "event_title": e["title"],
        })
    print(json.dumps({"ok": True, "due": due, "now": now.isoformat()}))
    raise SystemExit

if op == "mark-reminded":
    raw = args[0] if args else sys.stdin.read()
    try:
        payload = json.loads(raw)
    except Exception as ex:
        print(json.dumps({"ok": False, "error": f"json:{ex}"}))
        raise SystemExit(1)
    eid = str(payload.get("id") or "")
    key = str(payload.get("key") or "")
    if not eid or not key:
        print(json.dumps({"ok": False, "error": "missing"}))
        raise SystemExit(1)
    found = False
    for i, e in enumerate(events):
        if e["id"] == eid:
            rem = dict(e.get("reminded") or {})
            rem[key] = True
            e["reminded"] = rem
            events[i] = e
            found = True
            break
    if not found:
        print(json.dumps({"ok": False, "error": "not_found"}))
        raise SystemExit(1)
    data["events"] = events
    save(data)
    print(json.dumps({"ok": True}))
    raise SystemExit

print(json.dumps({"ok": False, "error": "usage"}))
sys.exit(1)
PY
