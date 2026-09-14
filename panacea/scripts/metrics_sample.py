#!/usr/bin/env python3
"""Uma amostra leve de métricas — fonte partilhável (rice / history / futuro Bonsai).

Saída: uma linha JSON em stdout.
Estado de delta (net/disk) em /dev/shm (RAM) — sem SSD.
Não inventa valores: campos ausentes omitidos ou null.
"""
from __future__ import annotations

import json
import os
import time
from pathlib import Path

STATE = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "panacea-metrics.state"


def read_cpu_pct(dt: float = 0.25) -> float | None:
    def snap():
        with open("/proc/stat") as f:
            parts = f.readline().split()
        vals = list(map(int, parts[1:]))
        idle = vals[3] + (vals[4] if len(vals) > 4 else 0)
        total = sum(vals)
        return idle, total

    i1, t1 = snap()
    time.sleep(dt)
    i2, t2 = snap()
    d_tot = t2 - t1
    d_idle = i2 - i1
    if d_tot <= 0:
        return None
    return round((d_tot - d_idle) * 100.0 / d_tot, 1)


def mem_info():
    kv = {}
    with open("/proc/meminfo") as f:
        for line in f:
            p = line.split()
            if len(p) >= 2 and p[0].endswith(":"):
                kv[p[0][:-1]] = int(p[1])  # kB
    total = kv.get("MemTotal", 0) * 1024
    avail = kv.get("MemAvailable", 0) * 1024
    used = max(0, total - avail)
    pct = round(used * 100.0 / total, 1) if total else None
    return pct, used, avail, total


def loadavg():
    try:
        a = open("/proc/loadavg").read().split()[:3]
        return [float(x) for x in a]
    except Exception:
        return None


def hwmon_temp(names: set[str]) -> float | None:
    base = Path("/sys/class/hwmon")
    if not base.is_dir():
        return None
    for h in base.iterdir():
        try:
            name = (h / "name").read_text().strip()
        except Exception:
            continue
        if name not in names:
            continue
        try:
            return int((h / "temp1_input").read_text().strip()) / 1000.0
        except Exception:
            continue
    return None


def gpu_busy() -> float | None:
    for d in Path("/sys/class/drm").glob("card*/device"):
        p = d / "gpu_busy_percent"
        if p.is_file():
            try:
                return float(p.read_text().strip())
            except Exception:
                pass
    return None


def vram() -> tuple[int | None, int | None]:
    # amdgpu: mem_info_vram_used / total (bytes)
    for d in Path("/sys/class/drm").glob("card*/device"):
        u, t = d / "mem_info_vram_used", d / "mem_info_vram_total"
        if u.is_file() and t.is_file():
            try:
                return int(u.read_text().strip()), int(t.read_text().strip())
            except Exception:
                pass
    return None, None


def default_iface() -> str | None:
    try:
        for line in open("/proc/net/route"):
            parts = line.split()
            if len(parts) >= 2 and parts[1] == "00000000":
                return parts[0]
    except Exception:
        pass
    return None


def net_bytes(iface: str) -> tuple[int, int]:
    rx = int(Path(f"/sys/class/net/{iface}/statistics/rx_bytes").read_text())
    tx = int(Path(f"/sys/class/net/{iface}/statistics/tx_bytes").read_text())
    return rx, tx


def disk_sectors() -> tuple[int, int]:
    """Soma read/write sectors de discos de topo."""
    r = w = 0
    with open("/proc/diskstats") as f:
        for line in f:
            p = line.split()
            if len(p) < 14:
                continue
            name = p[2]
            if name.startswith(("loop", "dm-", "sr", "zram")):
                continue
            if name.startswith("nvme") and "p" in name:
                continue
            if (not name.startswith("nvme")) and name[-1].isdigit():
                continue
            r += int(p[5])
            w += int(p[9])
    return r, w


def load_state():
    try:
        return json.loads(STATE.read_text())
    except Exception:
        return {}


def save_state(st: dict):
    try:
        STATE.write_text(json.dumps(st))
    except Exception:
        pass


def main():
    now = time.time()
    cpu = read_cpu_pct(0.2)
    mem_pct, mem_used, mem_avail, mem_total = mem_info()
    la = loadavg()
    tcpu = hwmon_temp({"k10temp", "coretemp", "zenpower", "cpu_thermal", "acpitz"})
    gpu = gpu_busy()
    tgpu = hwmon_temp({"amdgpu", "nouveau", "radeon", "i915", "nvidia"})
    v_used, v_total = vram()

    st = load_state()
    iface = default_iface()
    rx_rate = tx_rate = None
    read_bps = write_bps = None

    if iface:
        try:
            rx, tx = net_bytes(iface)
            prev = st.get("net")
            if prev and prev.get("iface") == iface and now > prev["t"]:
                dt = now - prev["t"]
                if dt > 0.05:
                    rx_rate = max(0, int((rx - prev["rx"]) / dt))
                    tx_rate = max(0, int((tx - prev["tx"]) / dt))
            st["net"] = {"iface": iface, "rx": rx, "tx": tx, "t": now}
        except Exception:
            pass

    try:
        rs, ws = disk_sectors()
        prev = st.get("disk")
        if prev and now > prev["t"]:
            dt = now - prev["t"]
            if dt > 0.05:
                read_bps = max(0, int((rs - prev["r"]) * 512 / dt))
                write_bps = max(0, int((ws - prev["w"]) * 512 / dt))
        st["disk"] = {"r": rs, "w": ws, "t": now}
    except Exception:
        pass

    save_state(st)

    out = {
        "ts": int(now),
        "cpu_pct": cpu,
        "mem_pct": mem_pct,
        "mem_used": mem_used,
        "mem_avail": mem_avail,
        "mem_total": mem_total,
        "loadavg": la,
        "cpu_temp": tcpu,
        "gpu_pct": gpu,
        "gpu_temp": tgpu,
        "vram_used": v_used,
        "vram_total": v_total,
        "iface": iface,
        "rx_rate": rx_rate,
        "tx_rate": tx_rate,
        "read_bps": read_bps,
        "write_bps": write_bps,
    }
    # remove nulls opcionais? manter nulls para UI saber N/A
    print(json.dumps(out, separators=(",", ":")))


if __name__ == "__main__":
    main()
