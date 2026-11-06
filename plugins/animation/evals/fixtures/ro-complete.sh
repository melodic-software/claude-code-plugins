#!/usr/bin/env bash
# Completes the work/ that ro-workdir.sh wrote: a trace and a source drawing for every indexed drawing.
# With a duration in seconds, first re-indexes work/ to that length at 8 drawings a second.
set -euo pipefail
python3 - "${1:-}" <<'PY'
import json, struct, sys, zlib
from pathlib import Path

work = Path("work")
idx = json.loads((work / "d/index.json").read_text(encoding="utf-8"))
if sys.argv[1]:
    n = round(float(sys.argv[1]) * 8)
    idx = {"w": idx["w"], "h": idx["h"], "duration": n / 8,
           "drawings": [[k, round(k / 8, 6), round((k + 1) / 8, 6)] for k in range(n)]}
    (work / "d/index.json").write_text(json.dumps(idx), encoding="utf-8")
w, h = idx["w"], idx["h"]


def png(path, k):
    paper, ink = b"\xef\xe6\xd2", b"\x14\x11\x0f"
    x0 = 200 + (k * 7) % 240
    rows = []
    for y in range(h):
        row = paper * w
        if 180 <= y < 400:
            row = paper * x0 + ink * 160 + paper * (w - x0 - 160)
        rows.append(b"\x00" + row)
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(b"".join(rows), 9)) + chunk(b"IEND", b""))


(work / "src").mkdir(parents=True, exist_ok=True)
for k, pts, t1 in idx["drawings"]:
    t = work / f"d/d{k:03d}.json"
    if not t.exists():
        t.write_text(json.dumps({"k": k, "pts": pts, "t1": t1, "w": w, "h": h, "S": 2, "eps": 0.6, "interp": 1,
                                 "sharp": [2.0, 0.9], "levels": [50, 90, 165, 205], "T": 118, "t_color": "#14110f",
                                 "paths": [[[300, 210], [312, 232], [319, 248], [327, 259], [300, 210]]],
                                 "tones": [{"lv": 90, "color": "#5b5249", "paths": [[[100, 100], [140, 100], [140, 140], [100, 100]]]}]},
                                separators=(",", ":")), encoding="utf-8")
    png(work / f"src/d{k:03d}.png", k)
PY
