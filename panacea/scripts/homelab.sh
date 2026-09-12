#!/usr/bin/env bash
# Panacea ↔ Gaab Homelab bridge. JSON stdout only. No ollama pull. No root by default.
# Usage: homelab.sh <command> [args...]
set -euo pipefail

HOME_DIR="${HOME:-}"
HL="${GAAB_HOMELAB_DIR:-$HOME_DIR/.config/gaab-homelab}"
SVC_DIR="$HL/services"
PROJ_DIR="$HL/projects"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME_DIR/.config}/systemd/user"

mkdir -p "$SVC_DIR" "$PROJ_DIR" "$HL/config" "$UNIT_DIR"

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()[:-1] if False else sys.argv[1]))' "$1" 2>/dev/null \
    || printf '"%s"' "${1//\"/\\\"}"
}

cmd_hub() {
  python3 - <<'PY'
import json, os, subprocess, shutil, time

def sh(c):
    try:
        return subprocess.check_output(c, shell=True, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ""

def active(unit):
    return sh(f"systemctl is-active {unit} 2>/dev/null") == "active"

def user_active(unit):
    return sh(f"systemctl --user is-active {unit} 2>/dev/null") == "active"

# load avg / mem quick
mem = sh("free -b | awk '/^[Mm]em/{if($2>0) printf \"%d\", $3*100/$2; else print 0}'")
load = sh("cut -d' ' -f1 /proc/loadavg")

docker_ok = shutil.which("docker") and sh("docker info >/dev/null 2>&1 && echo 1") == "1"
ollama_ok = shutil.which("ollama") and sh("curl -fsS --max-time 1 http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && echo 1") == "1"
ssh_ok = active("ssh") or active("sshd")

# failed user services (gaab-*)
failed = sh("systemctl --user --failed --no-legend 2>/dev/null | awk '{print $1}' | grep -E '^gaab-' | wc -l") or "0"

# disk root
root_pct = sh("df -P / | awk 'NR==2{gsub(/%/,\"\",$5); print $5}'")

sections = [
    {"id": "sys", "label": "SYS", "ok": True, "hint": f"load {load} · mem {mem}%"},
    {"id": "net", "label": "NET", "ok": True, "hint": "network"},
    {"id": "dev", "label": "DEV", "ok": True, "hint": "projects"},
    {"id": "run", "label": "RUN", "ok": int(failed) == 0, "hint": f"{failed} failed" if int(failed) else "services"},
    {"id": "logs", "label": "LOGS", "ok": True, "hint": "journal"},
    {"id": "docker", "label": "DOCKER", "ok": bool(docker_ok), "hint": "online" if docker_ok else "offline"},
    {"id": "ai", "label": "AI", "ok": bool(ollama_ok), "hint": "ollama" if ollama_ok else "offline"},
    {"id": "storage", "label": "STORAGE", "ok": (int(root_pct or 0) < 90), "hint": f"/ {root_pct}%"},
]
print(json.dumps({
    "hostname": sh("hostname"),
    "ssh": bool(ssh_ok),
    "docker": bool(docker_ok),
    "ollama": bool(ollama_ok),
    "failed_services": int(failed),
    "sections": sections,
    "ts": int(time.time() * 1000),
}))
PY
}

cmd_sys() {
  # Prefer sibling sysload.sh next to this script
  local here line cpu=0 mem=0 gpu=0 tcpu=0 tgpu=0
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  line="$("$here/sysload.sh" 2>/dev/null || true)"
  IFS='|' read -r cpu mem gpu tcpu tgpu <<<"${line}"
  python3 - "${cpu:-0}" "${mem:-0}" "${gpu:-0}" "${tcpu:-0}" "${tgpu:-0}" <<'PY'
import json, os, sys, subprocess, platform, time

def sh(c):
    try:
        return subprocess.check_output(c, shell=True, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ""

cpu, mem, gpu, tcpu, tgpu = sys.argv[1:6]
uptime = sh("uptime -p").removeprefix("up ")
kernel = platform.release()
host = sh("hostname")
osname = ""
if os.path.exists("/etc/os-release"):
    for line in open("/etc/os-release"):
        if line.startswith("PRETTY_NAME="):
            osname = line.split("=",1)[1].strip().strip('"')
vram = sh("rocm-smi --showmeminfo vram 2>/dev/null | awk '/Total Memory/{print $NF; exit}'") \
    or sh("nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -1") \
    or ""
print(json.dumps({
    "cpu_pct": float(cpu or 0),
    "mem_pct": float(mem or 0),
    "gpu_pct": float(gpu or 0),
    "cpu_temp": float(tcpu or 0),
    "gpu_temp": float(tgpu or 0),
    "vram": vram,
    "uptime": uptime,
    "kernel": kernel,
    "hostname": host,
    "os": osname,
}))
PY
}

cmd_net() {
  python3 - <<'PY'
import json, subprocess, shutil

def sh(c):
    try:
        return subprocess.check_output(c, shell=True, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ""

iface = sh("ip -br route show default 2>/dev/null | awk '{print $5; exit}'")
ip = sh(f"ip -4 -br addr show {iface} 2>/dev/null | awk '{{print $3}}'") if iface else ""
gw = sh("ip -br route show default 2>/dev/null | awk '{print $3; exit}'")
dns = sh("resolvectl dns 2>/dev/null | awk 'NR==1{print $2; exit}'") or sh("grep ^nameserver /etc/resolv.conf | awk '{print $2; exit}'")
rx = sh(f"cat /sys/class/net/{iface}/statistics/rx_bytes 2>/dev/null") if iface else "0"
tx = sh(f"cat /sys/class/net/{iface}/statistics/tx_bytes 2>/dev/null") if iface else "0"
ping = sh("ping -c1 -W1 1.1.1.1 >/dev/null 2>&1 && echo ok || echo fail")
ssh = sh("systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null")
print(json.dumps({
    "iface": iface,
    "ip": ip,
    "gateway": gw,
    "dns": dns,
    "rx_bytes": int(rx or 0),
    "tx_bytes": int(tx or 0),
    "internet": ping == "ok",
    "ssh": ssh == "active",
    "dns_ok": bool(dns),
}))
PY
}

cmd_storage() {
  python3 - <<'PY'
import json, subprocess

def sh(c):
    try:
        return subprocess.check_output(c, shell=True, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ""

def df_line(path):
    # size used avail pct
    o = sh(f"df -P {path} | awk 'NR==2{{print $2,$3,$4,$5,$6}}'")
    if not o: return None
    a = o.split()
    return {"size_kb": int(a[0]), "used_kb": int(a[1]), "avail_kb": int(a[2]), "pct": int(a[3].rstrip('%')), "mount": a[4]}

disks = []
raw = sh("lsblk -d -o NAME,SIZE,MODEL,TRAN,TYPE -J")
try:
    import json as J
    for d in J.loads(raw).get("blockdevices", []):
        if d.get("type") == "disk":
            disks.append(d)
except Exception:
    pass

smart = sh("sudo -n smartctl -H /dev/nvme0n1 2>/dev/null | awk -F: '/overall-health|SMART overall/{print $2}'") \
     or sh("smartctl -H /dev/nvme0n1 2>/dev/null | awk -F: '/overall-health|SMART overall/{print $2}'") \
     or "unknown"

print(json.dumps({
    "root": df_line("/"),
    "srv": df_line("/srv"),
    "disks": disks,
    "health": smart.strip() if smart else "unknown",
}))
PY
}

cmd_docker() {
  python3 - <<'PY'
import json, subprocess, shutil

def sh(c):
    try:
        return subprocess.check_output(c, shell=True, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ""

if not shutil.which("docker"):
    print(json.dumps({"ok": False, "containers": []}))
    raise SystemExit
raw = sh("docker ps -a --format '{{json .}}'")
containers = []
for line in raw.splitlines():
    if not line.strip():
        continue
    try:
        import json as J
        o = J.loads(line)
        containers.append({
            "id": o.get("ID", "")[:12],
            "name": o.get("Names", ""),
            "image": o.get("Image", ""),
            "status": o.get("Status", ""),
            "state": o.get("State", ""),
            "ports": o.get("Ports", ""),
            "running": str(o.get("State","")).lower() == "running",
        })
    except Exception:
        pass
print(json.dumps({"ok": True, "containers": containers}))
PY
}

cmd_docker_action() {
  local action="$1" name="$2"
  case "$action" in
    restart) docker restart "$name" >/dev/null ;;
    stop) docker stop "$name" >/dev/null ;;
    start) docker start "$name" >/dev/null ;;
    logs) docker logs --tail 80 "$name" 2>&1 | python3 -c 'import json,sys; print(json.dumps({"lines":sys.stdin.read().splitlines()}))'; return ;;
    *) echo '{"ok":false,"error":"bad action"}'; return 1 ;;
  esac
  echo '{"ok":true}'
}

cmd_ai() {
  python3 - <<'PY'
import json, subprocess, shutil

def sh(c):
    try:
        return subprocess.check_output(c, shell=True, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ""

online = False
models = []
if shutil.which("ollama"):
    tags = sh("curl -fsS --max-time 2 http://127.0.0.1:11434/api/tags")
    if tags:
        online = True
        try:
            import json as J
            models = [m.get("name","") for m in J.loads(tags).get("models", [])]
        except Exception:
            models = []
gpu = sh("lspci -nn 2>/dev/null | grep -iE 'vga|3d|display' | head -1")
print(json.dumps({
    "online": online,
    "endpoint": "127.0.0.1:11434",
    "models": models,
    "model_count": len(models),
    "gpu": gpu,
    "note": "bootstrap never pulls models",
}))
PY
}

cmd_projects() {
  python3 - <<'PY'
import json, os, subprocess
home = os.path.expanduser("~")
roots = [
    os.path.join(home, "dev", "projects"),
    os.path.join(home, "Documentos", "gitHub"),
]
proj_cfg = os.path.expanduser("~/.config/gaab-homelab/projects")
items = []
seen = set()

def add(path, name=None):
    path = os.path.abspath(path)
    if path in seen or not os.path.isdir(path):
        return
    seen.add(path)
    git = os.path.isdir(os.path.join(path, ".git"))
    branch = ""
    dirty = False
    if git:
        try:
            branch = subprocess.check_output(["git", "-C", path, "rev-parse", "--abbrev-ref", "HEAD"], text=True, stderr=subprocess.DEVNULL).strip()
            st = subprocess.check_output(["git", "-C", path, "status", "--porcelain"], text=True, stderr=subprocess.DEVNULL)
            dirty = bool(st.strip())
        except Exception:
            pass
    items.append({
        "name": name or os.path.basename(path),
        "path": path,
        "git": git,
        "branch": branch,
        "clean": not dirty,
    })

# explicit project files
if os.path.isdir(proj_cfg):
    for fn in sorted(os.listdir(proj_cfg)):
        if not fn.endswith((".json", ".yaml", ".yml")):
            continue
        p = os.path.join(proj_cfg, fn)
        try:
            raw = open(p).read()
            if fn.endswith(".json"):
                d = json.loads(raw)
                add(os.path.expanduser(d.get("directory") or d.get("path", "")), d.get("name"))
        except Exception:
            pass

for root in roots:
    if not os.path.isdir(root):
        continue
    for name in sorted(os.listdir(root))[:40]:
        if name.startswith("."):
            continue
        add(os.path.join(root, name))

print(json.dumps({"projects": items}))
PY
}

unit_name() {
  # ascii-engine → gaab-ascii-engine.service
  local n="$1"
  n="$(printf '%s' "$n" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9-' '-' | sed 's/^-//;s/-$//')"
  printf 'gaab-%s.service' "$n"
}

cmd_services_list() {
  python3 - "$SVC_DIR" "$UNIT_DIR" <<'PY'
import json, os, subprocess, sys
svc_dir, unit_dir = sys.argv[1:3]
items = []

def user_prop(unit, prop):
    try:
        return subprocess.check_output(["systemctl", "--user", "show", unit, f"-p{prop}", "--value"], text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ""

for fn in sorted(os.listdir(svc_dir)) if os.path.isdir(svc_dir) else []:
    if not fn.endswith((".yaml", ".yml", ".json")):
        continue
    path = os.path.join(svc_dir, fn)
    name = os.path.splitext(fn)[0]
    meta = {"name": name, "directory": "", "command": "", "port": "", "persistent": True, "restart": "on-failure"}
    try:
        raw = open(path).read()
        # minimal yaml: key: value lines
        for line in raw.splitlines():
            if ":" not in line or line.strip().startswith("#"):
                continue
            k, _, v = line.partition(":")
            k, v = k.strip(), v.strip().strip('"').strip("'")
            if k in meta:
                if k == "persistent":
                    meta[k] = v.lower() in ("1", "true", "yes")
                elif k == "port" and v.isdigit():
                    meta[k] = int(v)
                else:
                    meta[k] = v
    except Exception:
        pass
    unit = f"gaab-{name.lower().replace(' ', '-')}.service"
    # normalize unit from filename
    import re
    slug = re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-')
    unit = f"gaab-{slug}.service"
    state = user_prop(unit, "ActiveState") or "inactive"
    sub = user_prop(unit, "SubState")
    pid = user_prop(unit, "MainPID")
    items.append({
        **meta,
        "unit": unit,
        "state": state,
        "sub_state": sub,
        "pid": int(pid) if pid.isdigit() else 0,
        "running": state == "active",
        "defined": os.path.exists(os.path.join(unit_dir, unit)),
    })
print(json.dumps({"services": items}))
PY
}

cmd_service_write_unit() {
  local file="$1"
  python3 - "$file" "$UNIT_DIR" <<'PY'
import os, re, sys, subprocess, shlex
path, unit_dir = sys.argv[1:3]
meta = {}
for line in open(path, encoding="utf-8"):
    if ":" not in line or line.strip().startswith("#"):
        continue
    k, _, v = line.partition(":")
    meta[k.strip()] = v.strip().strip('"').strip("'")
name = meta.get("name") or os.path.splitext(os.path.basename(path))[0]
slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
unit = f"gaab-{slug}.service"
directory = os.path.expanduser(meta.get("directory", "~"))
command = meta.get("command", "true")
restart = meta.get("restart", "on-failure")
boot_raw = meta.get("start_on_boot", meta.get("persistent", "true"))
boot = str(boot_raw).lower() in ("1", "true", "yes")
# shlex.quote → safe single-quoted arg for: bash -lc <cmd>
exec_cmd = shlex.quote(command)
body = f"""[Unit]
Description=Gaab Homelab — {name}
After=default.target

[Service]
Type=simple
WorkingDirectory={directory}
ExecStart=/bin/bash -lc {exec_cmd}
Restart={restart}
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
"""
os.makedirs(unit_dir, exist_ok=True)
open(os.path.join(unit_dir, unit), "w", encoding="utf-8").write(body)
subprocess.run(["systemctl", "--user", "daemon-reload"], check=False)
if boot:
    subprocess.run(["systemctl", "--user", "enable", unit], check=False)
print(unit)
PY
}

cmd_service_action() {
  local action="$1" name="$2"
  local slug unit
  slug="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9-' '-' | sed 's/^-//;s/-$//')"
  unit="gaab-${slug}.service"
  case "$action" in
    start) systemctl --user start "$unit" ;;
    stop) systemctl --user stop "$unit" ;;
    restart) systemctl --user restart "$unit" ;;
    status)
      systemctl --user status "$unit" --no-pager -l 2>&1 | python3 -c 'import json,sys; print(json.dumps({"text":sys.stdin.read()}))'
      return
      ;;
    logs)
      journalctl --user -u "$unit" -n 100 --no-pager 2>&1 | python3 -c 'import json,sys; print(json.dumps({"lines":sys.stdin.read().splitlines()}))'
      return
      ;;
    *) echo '{"ok":false}'; return 1 ;;
  esac
  echo '{"ok":true,"unit":"'"$unit"'"}'
}

cmd_service_create() {
  # args via env or stdin JSON — here: name dir command port boot restart
  local name="$1" directory="$2" command="$3" port="${4:-}" boot="${5:-true}" restart="${6:-on-failure}"
  local slug file
  slug="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9-' '-' | sed 's/^-//;s/-$//')"
  file="$SVC_DIR/${slug}.yaml"
  cat >"$file" <<EOF
name: ${name}
directory: ${directory}
command: ${command}
port: ${port}
persistent: true
start_on_boot: ${boot}
restart: ${restart}
EOF
  local unit
  unit="$(cmd_service_write_unit "$file")"
  echo "{\"ok\":true,\"file\":\"$file\",\"unit\":\"$unit\"}"
}

cmd_logs() {
  local target="${1:-system}"
  case "$target" in
    system|SYSTEM)
      journalctl -n 80 --no-pager 2>&1 | python3 -c 'import json,sys; print(json.dumps({"target":"system","lines":sys.stdin.read().splitlines()}))'
      ;;
    ssh|SSH)
      journalctl -u ssh -u sshd -n 80 --no-pager 2>&1 | python3 -c 'import json,sys; print(json.dumps({"target":"ssh","lines":sys.stdin.read().splitlines()}))'
      ;;
    ollama|OLLAMA|ai|AI)
      journalctl -u ollama -n 80 --no-pager 2>&1 | python3 -c 'import json,sys; print(json.dumps({"target":"ollama","lines":sys.stdin.read().splitlines()}))'
      ;;
    docker|DOCKER)
      journalctl -u docker -n 80 --no-pager 2>&1 | python3 -c 'import json,sys; print(json.dumps({"target":"docker","lines":sys.stdin.read().splitlines()}))'
      ;;
    *)
      # assume gaab service name
      cmd_service_action logs "$target"
      ;;
  esac
}

cmd_ensure_dirs() {
  mkdir -p "$HL"/{services,projects,config,scripts}
  echo '{"ok":true,"dir":"'"$HL"'"}'
}

# ---------------- main
op="${1:-hub}"
shift || true
case "$op" in
  hub) cmd_hub ;;
  sys) cmd_sys ;;
  net) cmd_net ;;
  storage) cmd_storage ;;
  docker) cmd_docker ;;
  docker-action) cmd_docker_action "$@" ;;
  ai) cmd_ai ;;
  projects) cmd_projects ;;
  services|services-list) cmd_services_list ;;
  service-create) cmd_service_create "$@" ;;
  service-start) cmd_service_action start "$@" ;;
  service-stop) cmd_service_action stop "$@" ;;
  service-restart) cmd_service_action restart "$@" ;;
  service-logs) cmd_service_action logs "$@" ;;
  service-status) cmd_service_action status "$@" ;;
  service-install-unit)
    f="$1"
    cmd_service_write_unit "$f"
    ;;
  logs) cmd_logs "$@" ;;
  ensure) cmd_ensure_dirs ;;
  *) echo "{\"error\":\"unknown command\",\"cmd\":\"$op\"}"; exit 1 ;;
esac
