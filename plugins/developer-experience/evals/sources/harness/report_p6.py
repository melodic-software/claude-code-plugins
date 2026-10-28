#!/usr/bin/env python3
"""Print the Phase 6 comparison tables from scored runs (score.json after judge/score_j.py).

Usage: python3 -I report_p6.py [--roots R1,R2,...] [--no-per-run] [--append-to FILE] [--help]

--roots   results roots merged into one run set (default: results). The first Phase 6 pass is
          --roots results-p2,results-p6a (Phase 2 baselines beside its A2 and held-out runs).
--no-per-run  omit the per-run record table.

Sections: per-run meta table, task-outcome comparison (A0/A1/A2 on Opus: per-run compared
totals, ranges, means, non-inferiority A2 >= A1 - 1 on cell means, overlap and saturation
flags), totals and superiority (a tie or a lower total is "not shown"), S5 #1, pass^k per P item
and pass/fail case (k = the cell's run count), fire rates per model, held-out. Exit 0.
"""

import json
import sys
from collections import defaultdict
from pathlib import Path

EVALS = Path(__file__).resolve().parent.parent
TASK = ["S1", "S3", "S4", "S5", "S6", "S7", "T1", "T3"]
HELD = ["H-build", "H-audit"]
FIRE = {"S1": "build-cli", "S4": "build-cli", "S5": "build-cli", "S3": "audit-tools", "S6": "audit-tools",
        "S7": "audit-tools", "H-build": "build-cli", "H-audit": "audit-tools"}
QUIET = ["S2", "Q-build", "Q-audit", "NM-explain", "NM-script"]
PASSFAIL = ["S2", "T2", "T4", "N1", "Q-build", "Q-audit", "NM-explain", "NM-script"]
ARMS = ("A0", "A1", "A2")


def load(roots):
    runs = defaultdict(list)
    for root in roots:
        for mp in sorted((EVALS / root).glob("*/*/*/run-*/meta.json")):
            meta = json.loads(mp.read_text())
            sp = mp.parent / "score.json"
            score = json.loads(sp.read_text()) if sp.exists() else None
            runs[(meta["scenario"], meta["arm"], meta["model_alias"])].append((meta, score))
    for v in runs.values():
        v.sort(key=lambda r: r[0]["run"])
    return runs


def total(score):
    if score is None or "compared_total_score" not in score:
        return None
    return score["compared_total_score"], score["compared_total_max"]


def fmt_cell(rs):
    vals = [v for _, s in rs if (v := total(s)) is not None]
    if not vals or len(vals) != len(rs):
        return None
    pts = [v[0] for v in vals]
    mx = max(v[1] for v in vals)
    return pts, mx, min(pts), max(pts), sum(pts) / len(pts)


def per_run(runs):
    print("## Per-run record\n")
    print("| Scenario | Arm | Model | Run | CLI | Model id | Turns | Output tokens | Duration s | Valid | Skill calls |")
    print("|---|---|---|---|---|---|---|---|---|---|---|")
    for (sc, arm, model), rs in sorted(runs.items()):
        for meta, score in rs:
            calls = ", ".join(s.split(":")[-1] for s in (score or {}).get("skill_calls", [])) or "-"
            print(f"| {sc} | {arm} | {model} | {meta['run']} | {meta['cli_version'].split()[0]} | "
                  f"{meta.get('model_id')} | {meta['totals']['num_turns']} | {meta['totals']['output_tokens']} | "
                  f"{meta['totals']['duration_ms'] / 1000:.0f} | {'yes' if meta['valid'] else 'NO'} | {calls} |")
    print()


def comparison(runs, scenarios, title):
    print(f"## {title}\n")
    print("| Scenario | Max | A0 per run | A0 range | A0 mean | A1 per run | A1 range | A1 mean "
          "| A2 per run | A2 range | A2 mean | NI (A2 >= A1 - 1) | A2 range overlaps | Saturated |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    totals = defaultdict(float)
    complete = []
    for sc in scenarios:
        cells = {a: fmt_cell(runs.get((sc, a, "opus"), [])) for a in ARMS}
        row = [sc, str(max((c[1] for c in cells.values() if c), default=0))]
        for a in ARMS:
            c = cells[a]
            row += ["n/a"] * 3 if not c else [", ".join(map(str, c[0])), f"{c[2]}-{c[3]}", f"{c[4]:.2f}"]
        c0, c1, c2 = cells["A0"], cells["A1"], cells["A2"]
        if c0 and c1 and c2:
            complete.append(sc)
            for a, c in (("A0", c0), ("A1", c1), ("A2", c2)):
                totals[a] += c[4]
            ni = "yes" if c2[4] >= c1[4] - 1 else "NO"
            ov = [a for a, c in (("A0", c0), ("A1", c1)) if c[2] <= c2[3] and c2[2] <= c[3]]
            sat = "yes" if all(c[2] == c[1] for c in (c0, c1, c2)) else "no"
            row += [ni, ", ".join(ov) or "none", sat]
        else:
            row += ["not run", "-", "-"]
        print("| " + " | ".join(row) + " |")
    print(f"\nTotals (sum of cell means over {', '.join(complete)}): "
          + ", ".join(f"{a} {totals[a]:.2f}" for a in ARMS))
    for a in ("A0", "A1"):
        d = totals["A2"] - totals[a]
        print(f"- A2 vs {a}: {d:+.2f} -> {'A2 higher' if d > 0 else 'not shown (tie or lower)'}")
    print()


def s5_item1(runs):
    print("## S5 #1 (excluded from totals), Opus\n")
    print("| Arm | Pass per run |")
    print("|---|---|")
    for a in ARMS:
        rs = runs.get(("S5", a, "opus"), [])
        print(f"| {a} | {', '.join(str((s or {}).get('s5_item1_pass')) for _, s in rs)} |")
    print()


def pass_fail(runs):
    print("## Plugin-arm pass/fail items, Opus (pass^k = every one of the cell's k runs passes)\n")
    print("| Case | Item | Per run | pass^k |")
    print("|---|---|---|---|")
    for sc in TASK + PASSFAIL + HELD:
        rs = runs.get((sc, "A2", "opus"), [])
        if not rs or any(s is None for _, s in rs):
            continue
        items = defaultdict(list)
        for _, s in rs:
            for it in s["items"]:
                if it["class"] == "P":
                    items[str(it["item"])].append(it["pass"])
        for num, vals in items.items():
            k = "pass" if all(v is True for v in vals) else ("unscored" if None in vals else "FAIL")
            print(f"| {sc} | {num} | {', '.join(str(v) for v in vals)} | {k} ({len(vals)} runs) |")
    print()


def fires(runs):
    print("## Fire / stays-quiet by model (A2)\n")
    print("| Model | Case | Expect | Per run (skill calls) | Pass |")
    print("|---|---|---|---|---|")
    for model in ("opus", "sonnet", "haiku"):
        for sc in list(FIRE) + PASSFAIL:
            rs = runs.get((sc, "A2", model), [])
            if not rs:
                continue
            calls = [(s or {}).get("skill_calls", []) for _, s in rs]
            if sc in FIRE:
                ok = [any(c.endswith(":" + FIRE[sc]) for c in cs) for cs in calls]
                expect = f"fires {FIRE[sc]}"
            elif sc in QUIET:
                ok = [s is not None and all(i["pass"] for i in s["items"] if i["class"] == "P") for _, s in rs]
                expect = "stays quiet (all checks)"
            else:
                ok = [None] * len(rs)
                expect = "(setup / named skill)"
            shown = "; ".join(",".join(c.split(":")[-1] for c in cs) or "none" for cs in calls)
            print(f"| {model} | {sc} | {expect} | {shown} | {sum(bool(o) for o in ok)}/{len(ok)} |")
    print()


def main(argv):
    args = argv[1:]
    if args[:1] in (["-h"], ["--help"]):
        print(__doc__)
        return 0
    if "--append-to" in args:
        i = args.index("--append-to")
        target = args[i + 1]
        rest = args[:i] + args[i + 2:]
        import contextlib
        import io
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            main(argv[:1] + rest)
        with open(target, "a", encoding="utf-8") as fh:
            fh.write(buf.getvalue().replace("\n## ", "\n### "))
        return 0
    roots = ["results"]
    if "--roots" in args:
        roots = args[args.index("--roots") + 1].split(",")
    runs = load(roots)
    if "--no-per-run" not in args:
        per_run(runs)
    if "--per-run-only" in args:
        return 0
    comparison(runs, TASK, "Task-outcome comparison (Opus, compared items, S5 #1 excluded)")
    s5_item1(runs)
    pass_fail(runs)
    fires(runs)
    comparison(runs, HELD, "Held-out (Opus, compared items, reported separately from the bar)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
