#!/usr/bin/env bash
# Writes work/: a rotoscope work directory with 60 indexed drawings, traces for drawings 12 and 40-50, and one override.
set -euo pipefail
mkdir -p work/d work/src
python3 - <<'PY'
import json

drawings = [[k, round(k / 8, 6), round((k + 1) / 8, 6)] for k in range(60)]
with open("work/d/index.json", "w", encoding="utf-8") as f:
    json.dump({"w": 768, "h": 576, "duration": 7.5, "drawings": drawings}, f)
for k in [12] + list(range(40, 51)):
    trace = {"k": k, "pts": k / 8, "t1": (k + 1) / 8, "w": 768, "h": 576, "S": 2, "eps": 0.6, "interp": 1,
             "sharp": [2.0, 0.9], "levels": [50, 90, 165, 205], "T": 118, "t_color": "#14110f",
             "paths": [[[300, 210], [312, 232], [319, 248], [327, 259], [300, 210]]],
             "tones": [{"lv": 90, "color": "#5b5249", "paths": [[[100, 100], [140, 100], [140, 140], [100, 100]]]}]}
    with open(f"work/d/d{k:03d}.json", "w", encoding="utf-8") as f:
        f.write(json.dumps(trace, separators=(",", ":")))
with open("work/overrides.json", "w", encoding="utf-8") as f:
    json.dump({"overrides": [{"k": [0, 30], "brush": {"bias": 0.18, "blur": 0.7},
                              "why": "sparse line art, replica too thin"}]}, f, indent=2)
PY
printf '%s\n' '# Learnings' '' '- run 1: drawings 0-30 too thin; bias 0.18, blur 0.7 took XOR from 1.9% to 0.8%' >work/learnings.md
