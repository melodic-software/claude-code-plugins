#!/usr/bin/env python3
"""Resolve chosen CI lane runs to their legs through a lane-transcript sink's metrics.jsonl.

Usage:
    lane_legs.py --sink DIR RUN [RUN ...]
    lane_legs.py --sink DIR [--lane STEM] [--last N] [--since YYYY-MM-DD] [--until YYYY-MM-DD]
                 [--outcome OUTCOME] [--model TEXT]

A RUN is a run URL or a bare run reference. A run reference selects every leg of that run; a URL
that names an attempt (`.../runs/<id>/attempts/<n>`) narrows to it. The filters select legs: the
lane (the workflow file's stem), the date window on the row's `date`, `--outcome` (`error` is every
leg whose `is_error` is true, `success` a success that did not error, else the stored subtype or
outcome), and `--model` (a substring of any model the leg used). `--last N` keeps the N newest runs
left. Run references and filters do not mix.

The sink layout and every row field are in docs/contracts/lane-transcripts/README.md. A row written
before the provider-neutral fields reads them from the GitHub ones (`run_id`, `job_id`), with no
`run_url`. A leg's `kind` is `subscription` or `fallback` when its key names one, else `key`; a
review leg's `chunk` is its trailing number, 1 when it has none, and null on any other leg.

Output: JSON on stdout, `{sink, runs, unmatched, pruned_legs}`, runs newest first, each with its
legs oldest first and each leg's transcript as an absolute path, null once pruned. Nothing here
opens a transcript. Exit 0 with at least one run, 1 with none, 2 on a usage or sink error.
Stdlib only; Python 3.10+.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import NoReturn

DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
RUN_URL = re.compile(r"/runs/(\d+)(?:/attempts/(\d+))?")
CHUNK = re.compile(r"-(\d+)$")


def fail(message: str) -> NoReturn:
    print(f"lane_legs.py: {message}", file=sys.stderr)
    sys.exit(2)


def read_rows(sink: Path) -> list[dict]:
    text = (sink / "metrics.jsonl").read_text(encoding="utf-8", errors="replace")
    # A last line with no newline is an append cut short, not a row.
    complete = text[: text.rfind("\n") + 1]
    rows = []
    for line in complete.splitlines():
        try:
            parsed = json.loads(line)
        except ValueError:
            continue
        if isinstance(parsed, dict):
            rows.append(parsed)
    return rows


def run_ref(row: dict) -> str:
    return str(row.get("run_ref") or row.get("run_id"))


def leg_key(row: dict) -> str:
    return str(row.get("leg_key") or row.get("job_id"))


def leg_kind(key: str) -> str:
    return next((kind for kind in ("subscription", "fallback") if f"-{kind}" in key), "key")


def leg_chunk(key: str) -> int | None:
    if "review" not in key:
        return None
    match = CHUNK.search(key)
    return int(match.group(1)) if match else 1


def has_outcome(row: dict, outcome: str) -> bool:
    if row.get("is_error") is not True:
        return row.get("outcome") == outcome
    return outcome == "error" or (outcome != "success" and (row.get("subtype") or row.get("outcome")) == outcome)


def parse_ref(token: str) -> tuple[str, int | None]:
    match = RUN_URL.search(token)
    if match:
        return match.group(1), int(match.group(2)) if match.group(2) else None
    return token, None


def matches_filters(row: dict, ns: argparse.Namespace) -> bool:
    models = [row.get("model"), *(row.get("models") or [])]
    return (
        (ns.lane is None or row.get("lane") == ns.lane)
        and (ns.model is None or any(isinstance(m, str) and ns.model in m for m in models))
        and (ns.outcome is None or has_outcome(row, ns.outcome))
        and (ns.since is None or str(row.get("date")) >= ns.since)
        and (ns.until is None or str(row.get("date")) <= ns.until)
    )


def leg_out(row: dict, sink: Path) -> dict:
    key = leg_key(row)
    stored = row.get("transcript")
    return {
        "leg_key": key,
        "kind": leg_kind(key),
        "chunk": leg_chunk(key),
        "created_at": row.get("created_at"),
        "outcome": row.get("outcome"),
        "subtype": row.get("subtype"),
        "is_error": row.get("is_error"),
        "api_error_status": row.get("api_error_status"),
        "model": row.get("model"),
        "models": row.get("models") or [],
        "num_turns": row.get("num_turns"),
        "duration_ms": row.get("duration_ms"),
        "transcript": str(sink / stored) if isinstance(stored, str) and stored else None,
    }


def group_runs(rows: list[dict], sink: Path) -> list[dict]:
    runs: dict[tuple[str, int], dict] = {}
    for row in sorted(rows, key=lambda r: str(r.get("created_at"))):
        key = (run_ref(row), int(row.get("run_attempt") or 1))
        run = runs.setdefault(
            key,
            {
                "provider": row.get("provider") or "github",
                "run_ref": key[0],
                "run_attempt": key[1],
                "run_url": row.get("run_url"),
                "lane": row.get("lane"),
                "workflow": row.get("workflow"),
                "event": row.get("event"),
                "head_branch": row.get("head_branch"),
                "run_conclusion": row.get("run_conclusion"),
                "date": row.get("date"),
                "legs": [],
            },
        )
        run["legs"].append(leg_out(row, sink))
    return sorted(runs.values(), key=lambda r: str(r["legs"][-1]["created_at"]), reverse=True)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="lane_legs.py", description=__doc__.splitlines()[0])
    parser.add_argument("--sink", required=True, type=Path)
    parser.add_argument("runs", nargs="*")
    parser.add_argument("--lane")
    parser.add_argument("--last", type=int)
    parser.add_argument("--since")
    parser.add_argument("--until")
    parser.add_argument("--outcome")
    parser.add_argument("--model")
    ns = parser.parse_args(argv)

    filters = [ns.lane, ns.last, ns.since, ns.until, ns.outcome, ns.model]
    if ns.runs and any(f is not None for f in filters):
        fail("give either run references or filters, not both")
    if not ns.runs and all(f is None for f in filters):
        fail("name runs, or select them with --lane, --since, --until, --outcome or --model")
    for date in (ns.since, ns.until):
        if date is not None and not DATE.match(date):
            fail("--since and --until take YYYY-MM-DD")
    if ns.last is not None and ns.last < 1:
        fail("--last takes a positive count")
    if not ns.sink.is_absolute():
        fail("the sink must be an absolute directory path")
    if not (ns.sink / "metrics.jsonl").is_file():
        fail(f"no metrics.jsonl under {ns.sink}")

    rows = read_rows(ns.sink)
    unmatched: list[str] = []
    if ns.runs:
        chosen: list[dict] = []
        for token in ns.runs:
            ref, attempt = parse_ref(token)
            found = [r for r in rows if run_ref(r) == ref and (attempt is None or int(r.get("run_attempt") or 1) == attempt)]
            if not found:
                unmatched.append(token)
            chosen.extend(r for r in found if r not in chosen)
        runs = group_runs(chosen, ns.sink)
    else:
        runs = group_runs([r for r in rows if matches_filters(r, ns)], ns.sink)
        if ns.last is not None:
            runs = runs[: ns.last]

    pruned = sum(1 for run in runs for leg in run["legs"] if leg["transcript"] is None)
    print(json.dumps({"sink": str(ns.sink), "runs": runs, "unmatched": unmatched, "pruned_legs": pruned}, indent=2))
    return 0 if runs else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
