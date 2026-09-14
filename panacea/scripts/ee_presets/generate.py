#!/usr/bin/env python3
"""Regenerate Panacea EasyEffects quick presets from live_eq template."""
import json, copy, os

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATE = os.path.expanduser("~/.config/easyeffects/output/live_eq.json")
OCT = [0, 3, 6, 9, 12, 15, 18, 21, 24, 27]

PRESETS = {
    "volume_boost": {"gains": [2.0, 2.5, 1.5, 0.5, 1.0, 1.5, 1.0, 0.5, 0.0, -0.5], "out": 3.0},
    "quality": {"gains": [-0.5, 0.0, 0.5, 0.0, 0.5, 1.0, 1.0, 0.5, 0.5, 0.0], "out": 0.0},
    "bass": {"gains": [6.0, 5.5, 4.0, 2.0, 0.5, 0.0, -0.5, -0.5, 0.0, 0.0], "out": 0.0},
    "detail": {"gains": [-1.0, -0.5, 0.0, 0.5, 1.0, 2.0, 2.5, 2.0, 1.5, 0.5], "out": 0.0},
    "gaming": {"gains": [-2.0, -1.5, -0.5, 0.5, 1.5, 2.5, 3.0, 2.0, 1.0, 0.0], "out": 1.0},
}


def set_curve(doc, gains_oct, out_gain=0.0):
    d = copy.deepcopy(doc)
    eq = d["output"]["equalizer"]
    eq["output-gain"] = float(out_gain)
    eq["input-gain"] = 0.0
    oct_g = {OCT[i]: gains_oct[i] for i in range(10)}
    for side in ("left", "right"):
        for k, b in eq[side].items():
            if not k.startswith("band"):
                continue
            idx = int(k[4:])
            lo = max([i for i in OCT if i <= idx], default=OCT[0])
            hi = min([i for i in OCT if i >= idx], default=OCT[-1])
            g = oct_g[lo] if lo == hi else oct_g[lo] * (1 - (idx - lo) / (hi - lo)) + oct_g[hi] * ((idx - lo) / (hi - lo))
            b["gain"] = round(float(g), 2)
            b["mode"] = "Bell"
            b["q"] = 1.0
    return d


def main():
    base = json.load(open(TEMPLATE))
    for pid, meta in PRESETS.items():
        doc = set_curve(base, meta["gains"], meta["out"])
        path = os.path.join(HERE, f"{pid}.json")
        with open(path, "w") as f:
            json.dump(doc, f, indent=4)
            f.write("\n")
        print("wrote", path)


if __name__ == "__main__":
    main()
