#!/usr/bin/env python3
"""Measure how many assistant turns discovery subagent dispatches take to finish.

Reads Claude Code session transcripts: every subagents/agent-*.jsonl that has a
sibling agent-*.meta.json. A turn is counted in the unit `maxTurns` uses (see
plugins/discovery/reference/parent-contract.md): one assistant message, however
many parallel tool calls it holds, so assistant records are grouped by
message.id and the distinct ids are counted.

Only counts, dates and agent types are printed, never transcript content.

Exit 0 = report written (an empty result is still a report)
Exit 2 = the transcripts root cannot be read, or a usage error

Usage:
  python3 turns-to-complete.py [--root DIR] [--agent-type A,B] [--since YYYY-MM-DD]
                               [--ceiling N] [--json]

A dispatch enters the statistics only when it finished: its last assistant
message has a stop_reason other than tool_use, or it reached the ceiling. Running,
cancelled and aborted dispatches are counted in a stderr note, not in the table.

Columns:
  turns        distinct assistant message ids in the dispatch
  hit_ceiling  yes when turns >= --ceiling (default 40) or a record carries
               stop_reason "max_turns"; else no
  resumed      yes when a user record that is not a tool result follows the
               ceiling turn in the same transcript; unknown at the ceiling
               without one (a resume that leaves no record is undetectable);
               n/a below the ceiling
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
from datetime import date
from pathlib import Path

DEFAULT_TYPES = (
    "discovery:researcher,discovery:explorer,"
    "discovery:intent-tracer,discovery:research-verifier"
)


def _is_tool_result(content: object) -> bool:
    return (
        isinstance(content, list)
        and bool(content)
        and all(isinstance(b, dict) and b.get("type") == "tool_result" for b in content)
    )


def analyze(jsonl: Path, ceiling: int) -> dict | None:
    """Return date, turns, hit_ceiling and resumed for one transcript, or None if unreadable."""
    ids: set[str] = set()
    first_ts = None
    stopped = False
    last_stop = None
    resumed = False
    try:
        with jsonl.open(encoding="utf-8") as fh:
            for line in fh:
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(rec, dict):
                    continue
                first_ts = first_ts or rec.get("timestamp")
                msg = rec.get("message")
                msg = msg if isinstance(msg, dict) else {}
                if rec.get("type") == "assistant" and msg.get("id"):
                    ids.add(msg["id"])
                    last_stop = msg.get("stop_reason")
                    stopped = stopped or last_stop == "max_turns"
                elif (
                    rec.get("type") == "user"
                    and (len(ids) >= ceiling or stopped)
                    and not _is_tool_result(msg.get("content"))
                ):
                    resumed = True
    except (OSError, UnicodeDecodeError):
        return None
    hit = len(ids) >= ceiling or stopped
    return {
        "complete": hit or last_stop not in (None, "tool_use"),
        "date": first_ts[:10]
        if isinstance(first_ts, str) and len(first_ts) >= 10
        else "unknown",
        "turns": len(ids),
        "hit_ceiling": hit,
        "resumed": ("yes" if resumed else "unknown") if hit else "n/a",
    }


def percentile(sorted_vals: list[int], p: float) -> int:
    return sorted_vals[max(1, math.ceil(p * len(sorted_vals))) - 1]


def summarize(rows: list[dict]) -> list[dict]:
    out = []
    for agent in sorted({r["agentType"] for r in rows}):
        mine = [r for r in rows if r["agentType"] == agent]
        turns = sorted(r["turns"] for r in mine)
        out.append(
            {
                "agentType": agent,
                "n": len(turns),
                "min": turns[0],
                "p50": percentile(turns, 0.5),
                "p90": percentile(turns, 0.9),
                "max": turns[-1],
                "at_ceiling": sum(r["hit_ceiling"] for r in mine),
            }
        )
    return out


def table(headers: list[str], body: list[list[object]]) -> str:
    lines = [
        "| " + " | ".join(headers) + " |",
        "|" + "|".join("---" for _ in headers) + "|",
    ]
    lines += ["| " + " | ".join(str(c) for c in row) + " |" for row in body]
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--root", default="~/.claude/projects", help="transcripts root")
    ap.add_argument(
        "--agent-type", default=DEFAULT_TYPES, help="comma-separated agentType filter"
    )
    ap.add_argument("--since", type=date.fromisoformat, metavar="YYYY-MM-DD")
    ap.add_argument("--ceiling", type=int, default=40, help="turn ceiling (default 40)")
    ap.add_argument("--json", action="store_true", help="emit JSON instead of markdown")
    args = ap.parse_args()

    root = Path(args.root).expanduser()
    try:
        list(os.scandir(root))
    except OSError as exc:
        print(f"error: cannot read root {root}: {exc.strerror}", file=sys.stderr)
        return 2

    wanted = {t.strip() for t in args.agent_type.split(",") if t.strip()}
    since = args.since.isoformat() if args.since else None
    rows: list[dict] = []
    skipped = 0
    unfinished = 0
    for dirpath, _, files in os.walk(root):
        for name in files:
            if not (name.startswith("agent-") and name.endswith(".jsonl")):
                continue
            meta = Path(dirpath, name[: -len(".jsonl")] + ".meta.json")
            if not meta.is_file():
                continue
            try:
                agent = json.loads(meta.read_text(encoding="utf-8")).get("agentType")
            except (OSError, ValueError, AttributeError):
                skipped += 1
                continue
            if agent not in wanted:
                continue
            info = analyze(Path(dirpath, name), args.ceiling)
            if info is None:
                skipped += 1
            elif not since or (info["date"][:1].isdigit() and info["date"] >= since):
                if info["complete"]:
                    rows.append({"agentType": agent, **info})
                else:
                    unfinished += 1

    rows.sort(key=lambda r: (r["date"], r["agentType"]))
    summary = summarize(rows)
    if skipped:
        print(f"note: {skipped} unreadable transcript(s) skipped", file=sys.stderr)
    if unfinished:
        print(
            f"note: {unfinished} unfinished dispatch(es) excluded "
            "(no final stop_reason, below the ceiling)",
            file=sys.stderr,
        )
    if args.json:
        print(json.dumps({"dispatches": rows, "summary": summary}, indent=2))
        return 0
    print(
        table(
            ["date", "agentType", "turns", "hit_ceiling", "resumed"],
            [
                [
                    r["date"],
                    r["agentType"],
                    r["turns"],
                    "yes" if r["hit_ceiling"] else "no",
                    r["resumed"],
                ]
                for r in rows
            ],
        )
    )
    print()
    cols = ("agentType", "n", "min", "p50", "p90", "max", "at_ceiling")
    print(table(list(cols), [[s[k] for k in cols] for s in summary]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
