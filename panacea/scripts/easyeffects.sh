#!/usr/bin/env bash
# EasyEffects bridge for Panacea AudioView — semantic ops only.
# status | bypass on|off|toggle | load <name> | band <index> <gain_db> | open | ensure
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRESET_DIR="${HERE}/ee_presets"
EE_OUT="${XDG_CONFIG_HOME:-$HOME/.config}/easyeffects/output"

ee() { command -v easyeffects >/dev/null 2>&1; }

# Copia presets oficiais do rice → ~/.config/easyeffects/output (idempotente)
cmd_ensure() {
  python3 - "$PRESET_DIR" "$EE_OUT" <<'PY'
import json, os, shutil, sys
src, dst = sys.argv[1], sys.argv[2]
os.makedirs(dst, exist_ok=True)
copied = []
reg_path = os.path.join(src, "registry.json")
ids = []
if os.path.isfile(reg_path):
    try:
        ids = [p["id"] for p in json.load(open(reg_path)).get("presets", [])]
    except Exception:
        ids = []
for name in ids:
    s = os.path.join(src, f"{name}.json")
    d = os.path.join(dst, f"{name}.json")
    if os.path.isfile(s):
        shutil.copy2(s, d)
        copied.append(name)
print(json.dumps({"ok": True, "copied": copied, "dir": dst}))
PY
}

cmd_status() {
  if ! ee; then
    echo '{"available":false,"bypass":false,"preset":"","presets":[],"bands":[],"eq":false,"quick_presets":[],"ok":false}'
    return
  fi
  # garante presets do rice sem spam
  cmd_ensure >/dev/null 2>&1 || true
  python3 - "$PRESET_DIR" <<'PY'
import json, subprocess, re, os, sys
from shutil import which

PRESET_DIR = sys.argv[1]

def run(args, timeout=4):
    try:
        return subprocess.check_output(["easyeffects", *args], text=True, stderr=subprocess.DEVNULL, timeout=timeout).strip()
    except Exception:
        return ""

def dconf_read(path):
    try:
        out = subprocess.check_output(["dconf", "read", path], text=True, stderr=subprocess.DEVNULL, timeout=2).strip()
        if not out:
            return None
        if out in ("true", "false"):
            return out == "true"
        try:
            return float(out)
        except ValueError:
            return out.strip("'\"")
    except Exception:
        return None

EQ_L = "/com/github/wwmm/easyeffects/streamoutputs/equalizer/0/leftchannel"
BAND_IDX = [0, 3, 6, 9, 12, 15, 18, 21, 24, 27]

def bands():
    out = []
    for i in BAND_IDX:
        freq = dconf_read(f"{EQ_L}/band{i}-frequency")
        gain = dconf_read(f"{EQ_L}/band{i}-gain")
        if gain is None:
            gain = 0.0
        if freq is None:
            continue
        out.append({"index": i, "freq": float(freq), "gain": float(gain)})
    return out

def quick_presets():
    reg = os.path.join(PRESET_DIR, "registry.json")
    try:
        return json.load(open(reg)).get("presets", [])
    except Exception:
        return []

raw_b = run(["-b", "3"])
bypass = False
for tok in re.findall(r"\b[0123]\b", raw_b):
    if tok == "1":
        bypass = True
    if tok in ("0", "2"):
        bypass = False
gb = dconf_read("/com/github/wwmm/easyeffects/bypass")
if isinstance(gb, bool):
    bypass = gb

presets = []
raw_p = run(["-p"])
m = re.search(r"(?:Saída|Output|salida)\s*:\s*(.*)", raw_p, re.I)
if m:
    presets = [x.strip() for x in m.group(1).replace(";", ",").split(",") if x.strip()]

preset = run(["-s", "output"]) or ""
pm = re.search(r":\s*(\S+)\s*$", preset)
if pm:
    preset = pm.group(1).rstrip(",")
elif ":" in preset:
    preset = preset.split(":")[-1].strip()

# dconf last-loaded as backup truth
last = dconf_read("/com/github/wwmm/easyeffects/last-loaded-output-preset")
if isinstance(last, str) and last and not preset:
    preset = last

b = bands()
print(json.dumps({
    "available": True,
    "ok": True,
    "bypass": bypass,
    "preset": preset,
    "presets": presets,
    "quick_presets": quick_presets(),
    "bands": b,
    "eq": len(b) > 0,
}))
PY
}

cmd_bypass() {
  local mode="${1:-state}"
  if ! ee; then echo '{"ok":false,"available":false}'; return 1; fi
  case "$mode" in
    on|1) easyeffects -b 1 >/dev/null 2>&1 || true ;;
    off|0|2) easyeffects -b 2 >/dev/null 2>&1 || true ;;
    toggle)
      if dconf read /com/github/wwmm/easyeffects/bypass 2>/dev/null | grep -q true; then
        easyeffects -b 2 >/dev/null 2>&1 || true
      else
        easyeffects -b 1 >/dev/null 2>&1 || true
      fi
      ;;
    state|*) ;;
  esac
  cmd_status
}

cmd_load() {
  local name="${1:-}"
  if ! ee; then echo '{"ok":false,"available":false,"error":"unavailable"}'; return 1; fi
  if [ -z "$name" ]; then echo '{"ok":false,"error":"name"}'; return 1; fi
  cmd_ensure >/dev/null 2>&1 || true
  easyeffects -l "$name" >/dev/null 2>&1 || true
  # EE aplica de forma assíncrona — poll até last-loaded/bands baterem
  python3 - "$name" "$PRESET_DIR" "$EE_OUT" <<'PY'
import json, subprocess, re, os, sys, time

want = sys.argv[1]
PRESET_DIR = sys.argv[2]
EE_OUT = sys.argv[3]

def run(args, timeout=4):
    try:
        return subprocess.check_output(["easyeffects", *args], text=True, stderr=subprocess.DEVNULL, timeout=timeout).strip()
    except Exception:
        return ""

def dconf_read(path):
    try:
        out = subprocess.check_output(["dconf", "read", path], text=True, stderr=subprocess.DEVNULL, timeout=2).strip()
        if not out:
            return None
        if out in ("true", "false"):
            return out == "true"
        try:
            return float(out)
        except ValueError:
            return out.strip("'\"")
    except Exception:
        return None

EQ_L = "/com/github/wwmm/easyeffects/streamoutputs/equalizer/0/leftchannel"
BAND_IDX = [0, 3, 6, 9, 12, 15, 18, 21, 24, 27]

def bands():
    out = []
    for i in BAND_IDX:
        freq = dconf_read(f"{EQ_L}/band{i}-frequency")
        gain = dconf_read(f"{EQ_L}/band{i}-gain")
        if gain is None:
            gain = 0.0
        if freq is None:
            continue
        out.append({"index": i, "freq": float(freq), "gain": float(gain)})
    return out

def active_preset():
    last = dconf_read("/com/github/wwmm/easyeffects/last-loaded-output-preset")
    if isinstance(last, str) and last:
        return last
    preset = run(["-s", "output"]) or ""
    pm = re.search(r":\s*(\S+)\s*$", preset)
    if pm:
        return pm.group(1).rstrip(",")
    if ":" in preset:
        return preset.split(":")[-1].strip()
    return preset.strip()

def expected_gains():
    path = os.path.join(EE_OUT, f"{want}.json")
    if not os.path.isfile(path):
        path = os.path.join(PRESET_DIR, f"{want}.json")
    try:
        eq = json.load(open(path))["output"]["equalizer"]["left"]
        return [float(eq[f"band{i}"]["gain"]) for i in BAND_IDX]
    except Exception:
        return None

def gains_match(b, exp, tol=0.35):
    if not exp or len(b) != len(exp):
        return False
    for i, band in enumerate(b):
        if abs(float(band["gain"]) - exp[i]) > tol:
            return False
    return True

exp = expected_gains()
ok = False
preset = ""
b = []
deadline = time.time() + 2.5
while time.time() < deadline:
    preset = active_preset()
    b = bands()
    if exp is not None and gains_match(b, exp):
        ok = True
        preset = want
        break
    time.sleep(0.15)

# revalidação final (evita ok precoce)
b = bands()
if exp is not None:
    ok = gains_match(b, exp)
    if ok:
        preset = want
else:
    preset = active_preset()
    ok = preset == want
    b = bands()


gb = dconf_read("/com/github/wwmm/easyeffects/bypass")
bypass = bool(gb) if isinstance(gb, bool) else False

def quick_presets():
    try:
        return json.load(open(os.path.join(PRESET_DIR, "registry.json"))).get("presets", [])
    except Exception:
        return []

presets = []
raw_p = run(["-p"])
m = re.search(r"(?:Saída|Output|salida)\s*:\s*(.*)", raw_p, re.I)
if m:
    presets = [x.strip() for x in m.group(1).replace(";", ",").split(",") if x.strip()]

print(json.dumps({
    "available": True,
    "ok": ok,
    "error": "" if ok else "apply_failed",
    "bypass": bypass,
    "preset": preset if ok else (preset or ""),
    "presets": presets,
    "quick_presets": quick_presets(),
    "bands": b,
    "eq": len(b) > 0,
    "requested": want,
}))
PY
}

cmd_band() {
  local idx="${1:-}"
  local gain="${2:-}"
  if ! ee; then echo '{"ok":false,"available":false}'; return 1; fi
  if [ -z "$idx" ] || [ -z "$gain" ]; then echo '{"ok":false,"error":"usage"}'; return 1; fi
  python3 - "$idx" "$gain" <<'PY'
import json, subprocess, sys
from shutil import which

def dconf_write(path, value):
    try:
        subprocess.check_call(["dconf", "write", path, str(value)],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2)
        return True
    except Exception:
        return False

def dconf_read(path):
    try:
        out = subprocess.check_output(["dconf", "read", path], text=True, stderr=subprocess.DEVNULL, timeout=2).strip()
        if not out:
            return None
        try:
            return float(out)
        except ValueError:
            return None
    except Exception:
        return None

EQ_L = "/com/github/wwmm/easyeffects/streamoutputs/equalizer/0/leftchannel"
EQ_R = "/com/github/wwmm/easyeffects/streamoutputs/equalizer/0/rightchannel"
BAND_IDX = [0, 3, 6, 9, 12, 15, 18, 21, 24, 27]

idx = int(sys.argv[1])
gain = max(-24.0, min(24.0, float(sys.argv[2])))
ok = dconf_write(f"{EQ_L}/band{idx}-gain", gain) and dconf_write(f"{EQ_R}/band{idx}-gain", gain)

bands = []
for i in BAND_IDX:
    freq = dconf_read(f"{EQ_L}/band{i}-frequency")
    g = dconf_read(f"{EQ_L}/band{i}-gain")
    if g is None:
        g = 0.0
    if freq is None:
        continue
    bands.append({"index": i, "freq": float(freq), "gain": float(g)})

print(json.dumps({"ok": ok, "available": bool(which("easyeffects")), "bands": bands, "eq": len(bands) > 0}))
PY
}

cmd_open() {
  if ! ee; then echo '{"ok":false,"available":false}'; return 1; fi
  setsid easyeffects >/dev/null 2>&1 &
  echo '{"ok":true}'
}

op="${1:-status}"
shift || true
case "$op" in
  status) cmd_status ;;
  ensure) cmd_ensure ;;
  bypass) cmd_bypass "$@" ;;
  load) cmd_load "$@" ;;
  band) cmd_band "$@" ;;
  presets) cmd_status ;;
  open) cmd_open ;;
  *) echo '{"ok":false,"error":"usage"}'; exit 1 ;;
esac
