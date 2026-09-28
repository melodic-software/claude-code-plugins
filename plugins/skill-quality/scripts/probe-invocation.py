#!/usr/bin/env python3
"""Grade labeled queries against a skill's listing text.

Measures whether the description (plus optional when_to_use) would win a
description-driven auto-invocation match for realistic requests. Default grade
is listing-coverage: token overlap of the request against the listing, ranked
against competitor listings. No model is called.

Each probe file is JSON:
  skill, skill_md, competitors[], queries[{id, split, expect, request}]
  split is train or val; expect is trigger or hold.

Exit 0 on a successful report; 2 on usage or environment error.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

STOP = frozenset(
    """
    a an the to for of or and when use is this my a before every with from that
    it in in on as be not at by if vs via its our your than then so do does did
    any all each also into over under after while where which who whom
    """.split()
)
TOKEN = re.compile(r"[a-z0-9]+")
FM_FIELD = re.compile(r"^(description|when_to_use):\s*(.*)$")


def usage_error(msg: str) -> int:
    print(f"Error: {msg}", file=sys.stderr)
    return 2


def tokenize(text: str) -> set[str]:
    return {t for t in TOKEN.findall(text.lower()) if t not in STOP and len(t) > 1}


def listing_text(skill_md: Path) -> str:
    raw = skill_md.read_text(encoding="utf-8")
    if not raw.startswith("---"):
        raise ValueError(f"{skill_md}: no YAML frontmatter")
    parts = raw.split("---", 2)
    if len(parts) < 3:
        raise ValueError(f"{skill_md}: unclosed frontmatter")
    fields: dict[str, str] = {}
    for line in parts[1].splitlines():
        m = FM_FIELD.match(line)
        if not m:
            continue
        val = m.group(2).strip()
        if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
            val = val[1:-1]
        fields[m.group(1)] = val
    desc = fields.get("description", "")
    if not desc:
        raise ValueError(f"{skill_md}: frontmatter missing description")
    wtu = fields.get("when_to_use", "")
    return f"{desc} {wtu}".strip()


def score(query: str, listing: str) -> float:
    q = tokenize(query)
    if not q:
        return 0.0
    return len(q & tokenize(listing)) / len(q)


def resolve(path: str, base: Path) -> Path:
    p = Path(path)
    if p.is_absolute():
        return p
    cand = (base / p).resolve()
    if cand.exists():
        return cand
    return Path(path).resolve()


def load_probe(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    for key in ("skill", "skill_md", "queries"):
        if key not in data:
            raise ValueError(f"{path}: missing {key}")
    if not isinstance(data["queries"], list) or not data["queries"]:
        raise ValueError(f"{path}: queries must be a non-empty list")
    return data


def grade_probe(data: dict, probe_dir: Path) -> dict:
    skill_md = resolve(data["skill_md"], probe_dir)
    if not skill_md.is_file():
        raise ValueError(f"skill_md not found: {skill_md}")
    target_listing = listing_text(skill_md)
    competitors = []
    for raw in data.get("competitors") or []:
        cpath = resolve(raw, probe_dir)
        if not cpath.is_file():
            raise ValueError(f"competitor not found: {cpath}")
        competitors.append((str(cpath), listing_text(cpath)))

    splits = {"train": {"trigger": [0, 0], "hold": [0, 0]}, "val": {"trigger": [0, 0], "hold": [0, 0]}}
    cases = []
    for q in data["queries"]:
        qid = str(q.get("id") or "")
        split = q.get("split")
        expect = q.get("expect")
        request = q.get("request") or ""
        if split not in splits or expect not in ("trigger", "hold") or not qid or not request:
            raise ValueError(f"{qid or '?'}: need id, split train|val, expect trigger|hold, request")
        target_score = score(request, target_listing)
        ranked = [("target", target_score)]
        for cpath, clisting in competitors:
            ranked.append((cpath, score(request, clisting)))
        ranked.sort(key=lambda item: item[1], reverse=True)
        top_name, top_score = ranked[0]
        unique_top = top_score > 0 and sum(1 for _, s in ranked if s == top_score) == 1
        triggered = unique_top and top_name == "target"
        if expect == "trigger":
            passed = triggered
        else:
            passed = not triggered
        splits[split][expect][0] += int(passed)
        splits[split][expect][1] += 1
        cases.append(
            {
                "id": qid,
                "split": split,
                "expect": expect,
                "passed": passed,
                "triggered": triggered,
                "target_score": round(target_score, 4),
                "top": top_name,
                "top_score": round(top_score, 4),
            }
        )

    def rate(pair: list[int]) -> dict:
        ok, n = pair
        return {"passed": ok, "n": n, "rate": None if n == 0 else round(ok / n, 4)}

    report = {
        "skill": data["skill"],
        "mode": "listing-coverage",
        "skill_md": str(skill_md),
        "query_count": len(cases),
        "train": {
            "trigger": rate(splits["train"]["trigger"]),
            "hold": rate(splits["train"]["hold"]),
        },
        "val": {
            "trigger": rate(splits["val"]["trigger"]),
            "hold": rate(splits["val"]["hold"]),
        },
        "cases": cases,
    }
    return report


def print_human(report: dict) -> None:
    print(f"skill: {report['skill']}")
    print(f"mode: {report['mode']}")
    print(f"queries: {report['query_count']}")
    for split in ("train", "val"):
        trig = report[split]["trigger"]
        hold = report[split]["hold"]
        trig_s = "n/a" if trig["rate"] is None else f"{trig['rate']:.2%} ({trig['passed']}/{trig['n']})"
        hold_s = "n/a" if hold["rate"] is None else f"{hold['rate']:.2%} ({hold['passed']}/{hold['n']})"
        false_n = hold["n"] - hold["passed"]
        false_s = "n/a" if hold["n"] == 0 else f"{false_n / hold['n']:.2%} ({false_n}/{hold['n']})"
        print(f"{split}: trigger_rate={trig_s} hold_rate={hold_s} false_trigger_rate={false_s}")
    failed = [c["id"] for c in report["cases"] if not c["passed"]]
    if failed:
        print("failed: " + ", ".join(failed))
    else:
        print("failed: none")


def delta(current: dict, baseline: dict) -> None:
    print(f"compare: {current['skill']} vs baseline skill={baseline.get('skill')}")
    for split in ("train", "val"):
        for kind in ("trigger", "hold"):
            cur = current[split][kind]["rate"]
            base = baseline.get(split, {}).get(kind, {}).get("rate")
            if cur is None or base is None:
                print(f"{split}.{kind}: delta n/a")
                continue
            print(f"{split}.{kind}: {base:.2%} -> {cur:.2%} ({cur - base:+.2%})")


def default_probe_dir() -> Path:
    return Path(__file__).resolve().parent.parent / "skills" / "check" / "probes"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Grade labeled auto-invocation queries against skill listing text."
    )
    parser.add_argument(
        "probes",
        nargs="*",
        help="Probe JSON files. Default: bundled skills/check/probes/*.json",
    )
    parser.add_argument("--json", dest="json_out", help="Write the combined report JSON here")
    parser.add_argument("--compare", help="Baseline JSON from a prior run; print rate deltas")
    args = parser.parse_args(argv)

    paths = [Path(p) for p in args.probes]
    if not paths:
        bundled = sorted(default_probe_dir().glob("*.json"))
        if not bundled:
            return usage_error(f"no probe files under {default_probe_dir()}")
        paths = bundled

    reports = []
    for path in paths:
        if not path.is_file():
            return usage_error(f"probe file does not exist: {path}")
        try:
            data = load_probe(path)
            reports.append(grade_probe(data, path.parent))
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            return usage_error(str(exc))

    for i, report in enumerate(reports):
        if i:
            print("---")
        print_human(report)

    combined = reports[0] if len(reports) == 1 else {"reports": reports}
    if args.json_out:
        Path(args.json_out).write_text(json.dumps(combined, indent=2) + "\n", encoding="utf-8")
        print(f"json: {args.json_out}")

    if args.compare:
        base_path = Path(args.compare)
        if not base_path.is_file():
            return usage_error(f"baseline does not exist: {args.compare}")
        try:
            baseline = json.loads(base_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            return usage_error(f"baseline: {exc}")
        if "reports" in baseline:
            return usage_error("baseline must be a single-skill report")
        if len(reports) != 1:
            return usage_error("--compare requires exactly one probe file")
        print("---")
        delta(reports[0], baseline)

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
