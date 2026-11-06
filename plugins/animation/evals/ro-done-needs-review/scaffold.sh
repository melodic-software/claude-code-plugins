#!/usr/bin/env bash
# A complete rotoscope work directory whose full measure run passes every drawing (the measure.py table,
# its rep/heat/ab images and its learnings line); review.py has not run.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" work
bash "${here}/../fixtures/ro-workdir.sh"
bash "${here}/../fixtures/ro-complete.sh"
python3 - <<'PY'
import json, shutil
from pathlib import Path

work = Path("work")
ks = [k for k, *_ in json.loads((work / "d/index.json").read_text(encoding="utf-8"))["drawings"]]
out = work / "out/full"
for sub in ("rep", "heat", "ab"):
    (out / sub).mkdir(parents=True, exist_ok=True)
rows = []
for k in ks:
    src = work / f"src/d{k:03d}.png"
    for sub in ("rep", "heat", "ab"):
        shutil.copyfile(src, out / sub / f"d{k:03d}.png")
    floor = 0.21 + (k % 7) * 0.01
    xor = floor * (0.78 + (k % 5) * 0.05)
    rows.append(dict(k=k, pts=k / 8, xor=xor, floor=floor, rep=300 + 11 * (k % 9), srcpx=280 + 13 * (k % 8),
                     ssim=0.9862 - (k % 6) * 0.0009, ssim_e=0.9831 - (k % 4) * 0.0007, pe=0.9 + (k % 3) * 0.2))
lines = [f"# full d{ks[0]:03d}-d{ks[-1]:03d}  target: xor <= 1.2 x floor, ssim >= 0.98, ssim_e >= 0.98", "",
         "| k | pts | xor % | floor % | xor/floor | replica-only px | source-only px | ssim | ssim_e | paper_err | paper_d R,G,B | pass |",
         "|---|---|---|---|---|---|---|---|---|---|---|---|"]
lines += [f"| {r['k']} | {r['pts']:.3f} | {r['xor']:.3f} | {r['floor']:.3f} | {r['xor'] / r['floor']:.2f} | {r['rep']} | {r['srcpx']} | "
          f"{r['ssim']:.4f} | {r['ssim_e']:.4f} | {r['pe']:.2f} | +0.40,-0.20,+0.10 | yes |" for r in rows]
mean = lambda f: sum(r[f] for r in rows) / len(rows)
lines.append(f"| mean | | {mean('xor'):.3f} | {mean('floor'):.3f} | | | | {mean('ssim'):.4f} | {mean('ssim_e'):.4f} | "
             f"{mean('pe'):.2f} | +0.40,-0.20,+0.10 | {len(rows)}/{len(rows)} |")
(out / f"table-{ks[0]:03d}-{ks[-1]:03d}.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
worst = sorted(rows, key=lambda r: -r["xor"] / r["floor"])[:3]
with open(work / "learnings.md", "a", encoding="utf-8") as f:
    f.write(f"- 2026-11-05 measure full d{ks[0]:03d}-d{ks[-1]:03d}: {len(rows)}/{len(rows)} pass; mean xor {mean('xor'):.3f}%, "
            f"ssim {mean('ssim'):.4f}; worst xor/floor " + ", ".join(f"d{r['k']:03d} {r['xor'] / r['floor']:.2f}" for r in worst) + "\n")
PY
