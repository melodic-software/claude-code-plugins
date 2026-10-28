#!/usr/bin/env python3
"""Print a markdown table of scored runs: one row per (scenario, arm, model) cell.

Usage: python3 -I summarize.py [RESULTS_DIR] [--help]   (default: ../results)

Reads every run-*/meta.json and score.json. "At max" means every run of the cell reached
the cell's deterministic maximum (the per-cell part of the saturation flag; the flag
itself needs all three arms). Exit: 0 printed, 2 usage.
"""

import json
import sys
from collections import defaultdict
from pathlib import Path


def main(argv):
    if argv[1:] in (["-h"], ["--help"]):
        print(__doc__)
        return 0
    if len(argv) > 2:
        sys.stderr.write("usage: summarize.py [RESULTS_DIR]\n")
        return 2
    root = Path(argv[1]) if len(argv) == 2 else Path(__file__).resolve().parent.parent / "results"
    cells = defaultdict(list)
    for meta_path in sorted(root.glob("*/*/*/run-*/meta.json")):
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
        if meta["scenario"].startswith("SENT-"):
            continue
        score_path = meta_path.parent / "score.json"
        score = json.loads(score_path.read_text(encoding="utf-8")) if score_path.exists() else None
        cells[(meta["scenario"], meta["arm"], meta["model_alias"])].append((meta, score))
    print("| Scenario | Arm | Per-run D/T score | Range | At max | Turns | Duration s | Valid | Unscored J items |")
    print("|---|---|---|---|---|---|---|---|---|")
    for (scenario, arm, _), runs in sorted(cells.items()):
        runs.sort(key=lambda r: r[0]["run"])
        scores = [r[1]["compared_deterministic_score"] if r[1] else None for r in runs]
        maxes = {r[1]["compared_deterministic_max"] for r in runs if r[1]}
        mx = max(maxes) if maxes else 0
        known = [s for s in scores if s is not None]
        rng = f"{min(known)}-{max(known)}" if known else "n/a"
        at_max = "n/a" if mx == 0 else ("yes" if known and all(s == mx for s in known) else "no")
        turns = ", ".join(str(r[0]["totals"]["num_turns"]) for r in runs)
        dur = ", ".join(f"{r[0]['totals']['duration_ms'] / 1000:.0f}" for r in runs)
        valid = "all" if all(r[0]["valid"] for r in runs) else "NO"
        judge = runs[0][1]["unscored_judge_items"] if runs[0][1] else []
        per_run = ", ".join("?" if s is None else f"{s}/{mx}" for s in scores)
        print(f"| {scenario} | {arm} | {per_run} | {rng} | {at_max} | {turns} | {dur} | {valid} "
              f"| {', '.join(map(str, judge))} |")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
