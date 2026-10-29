#!/usr/bin/env python3
"""Merge calibrated Sonnet judge verdicts into every baseline run's score.json and print tables.

Usage: python3 -I score_j.py [--dry-run] [--root DIR:PREFIX[:ARMS[:SCENARIOS]] ...] [--help]

--root names a results root and the judge-input prefix its runs were built with (build_inputs.py
--prefix), optionally only for the comma-separated ARMS (default all; one root can hold arms
built with different prefixes) and the comma-separated SCENARIOS (default all); default results:
and results-rerun:rerun-.

Reads judge/status.json ({"<scenario>/<item>": {"version": N, "counted": bool}}) and the
verdict for each run's real sample in judge/calibration/sonnet-v<N>/<key>.jsonl (the scoring
call: the real samples are judged with the item's final instructions). A J item whose D part
exists (items.json "combine") passes only when both the D part and the verdict pass. Items
with counted=false are recorded with pass=null ("judge not calibrated"). D and T items and
compared_deterministic_* are left unchanged. Prints the per-cell table, the per-item pass
counts and the calibration table as markdown. Exit: 0 done, 1 a verdict is missing, 2 usage.
"""

import importlib.util
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
EVALS = HERE.parent


def _load_judge():
    spec = importlib.util.spec_from_file_location("judge_mod", HERE / "judge.py")
    if spec is None or spec.loader is None:
        raise SystemExit("cannot load judge/judge.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


judge = _load_judge()


def d_part(rule, ev):
    if rule is None:
        return None, None
    if rule == "and-scripts-intact":
        ok = "scripts/ intact=True" in ev
    elif rule == "and-nonzero-exit":
        m = re.search(r"exit=(-?\d+|None)", ev)
        ok = bool(m) and m.group(1) not in ("0", "None")
    elif rule == "and-paths-found":
        ok = "backticked paths not found=[]" in ev
    elif rule == "and-claude-path":
        ok = ".claude path named=True" in ev
    else:
        raise SystemExit(f"unknown combine rule {rule}")
    return ok, ev


def main(argv):
    if argv[1:] and argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0
    args = argv[1:]
    dry = "--dry-run" in args
    roots = [(args[i + 1].split(":") + ["", "", ""])[:4] for i, a in enumerate(args[:-1]) if a == "--root"]
    roots = roots or [["results", "", "", ""], ["results-rerun", "rerun-", "", ""]]
    items = judge.items()
    status = json.loads((HERE / "status.json").read_text())
    verdicts = {}
    for key, st in status.items():
        for row in judge.read_jsonl(HERE / "calibration" / f"sonnet-v{st['version']}" / f"{key}.jsonl"):
            verdicts[(key, row["sample"])] = row
        for row in judge.read_jsonl(HERE / "scores" / f"sonnet-v{st['version']}" / f"{key}.jsonl"):
            verdicts[(key, f"real-{row['sample']}")] = row
    missing = 0
    cells = defaultdict(list)
    item_pass = defaultdict(lambda: defaultdict(list))
    paths = [(sp, prefix) for root, prefix, arms, scs in roots
             for sp in EVALS.glob(f"{root}/*/A[012]/opus/run-*/score.json")
             if (not arms or sp.parent.parent.parent.name in arms.split(","))
             and (not scs or sp.parent.parent.parent.parent.name in scs.split(","))]
    for sp, prefix in sorted(paths):
        score = json.loads(sp.read_text())
        sc, arm, run = score["scenario"], score["arm"], score["run"]
        if sc.startswith("SENT-"):
            continue
        for it in score["items"]:
            key = f"{sc}/{it['item']}"
            if key not in items or key not in status:
                continue
            spec, st = items[key], status[key]
            row = verdicts.get((key, f"real-{prefix}{arm}-run{run}.md"))
            if row is None:
                print(f"missing verdict {key} {prefix}{arm} run {run}", file=sys.stderr)
                missing += 1
                continue
            if spec["combine"] == "and-d-pass":
                d_ok = bool(it.get("d_pass"))
            else:
                d_ok, _ = d_part(spec["combine"], it.get("d_evidence", it["evidence"]))
            it.setdefault("d_evidence", it["evidence"])
            j_ok = row["verdict"] == "PASS"
            combined = j_ok if d_ok is None else (j_ok and d_ok)
            it["pass"] = combined if st["counted"] else None
            it["judge"] = {"model": "sonnet", "model_ids": row["model_ids"],
                           "instructions_version": st["version"], "verdict": row["verdict"],
                           "d_part_pass": d_ok, "calibrated": st["counted"],
                           "reasoning": row["reasoning"][-600:]}
            it["evidence"] = (f"judge {row['verdict']} (sonnet, instructions v{st['version']})"
                              + ("" if d_ok is None else f"; D part pass={d_ok}")
                              + ("" if st["counted"] else "; judge not calibrated, not counted"))
            item_pass[key][prefix + arm].append(None if not st["counted"] else combined)
        # DEVIATIONS 2026-10-09: S5 #1 is excluded from the compared totals of every arm.
        for i in score["items"]:
            if sc == "S5" and str(i["item"]) == "1":
                i["excluded_from_totals"] = True
                score["s5_item1_pass"] = i["pass"]
        compared = [i for i in score["items"] if i["class"] == "C" and i["pass"] is not None
                    and not i.get("excluded_from_totals")]
        judged = [i for i in compared if i["grader"] == "J"]
        score["compared_judge_score"] = sum(1 for i in judged if i["pass"])
        score["compared_judge_max"] = len(judged)
        score["compared_total_score"] = sum(1 for i in compared if i["pass"])
        score["compared_total_max"] = len(compared)
        score["unscored_judge_items"] = [i["item"] for i in score["items"] if i["pass"] is None]
        score["plugin_arm_items"] = [{"item": i["item"], "pass": i["pass"]}
                                     for i in score["items"] if i["class"] == "P"]
        if not dry:
            sp.write_text(json.dumps(score, indent=2) + "\n")
        cells[(sc, prefix + arm)].append(score)

    print("| Scenario | Arm | Per-run total (D/T + J) | Range | Mean | At max | J part per run | Not counted |")
    print("|---|---|---|---|---|---|---|---|")
    at_max = {}
    for (sc, arm), runs in sorted(cells.items()):
        runs.sort(key=lambda s: s["run"])
        tot = [s["compared_total_score"] for s in runs]
        mx = max(s["compared_total_max"] for s in runs)
        at_max[(sc, arm)] = mx > 0 and all(t == mx for t in tot)
        jp = ", ".join(f"{s['compared_judge_score']}/{s['compared_judge_max']}" for s in runs)
        nc = ", ".join(map(str, runs[0]["unscored_judge_items"])) or "none"
        mean = sum(tot) / len(tot)
        print(f"| {sc} | {arm} | {', '.join(f'{t}/{mx}' for t in tot)} | {min(tot)}-{max(tot)} | {mean:.2f} "
              f"| {'yes' if at_max[(sc, arm)] else 'no'} | {jp} | {nc} |")
    print()
    print("| Scenario | Both baselines at max (saturated so far) |")
    print("|---|---|")
    for sc in sorted({k[0] for k in cells}):
        print(f"| {sc} | {'yes' if at_max.get((sc, 'A0')) and at_max.get((sc, 'A1')) else 'no'} |")
    print()
    print("| J item | Class | Pass count per cell |")
    print("|---|---|---|")
    for key in items:
        cols = ", ".join(f"{c} {sum(bool(v) for v in vs)}/{len(vs)}" + (" (n/c)" if None in vs else "")
                         for c, vs in sorted(item_pass[key].items()))
        print(f"| {key} | {items[key]['class']} | {cols} |")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
