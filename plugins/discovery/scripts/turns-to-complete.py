#!/usr/bin/env python3
"""Measure how many assistant turns discovery subagent dispatches take to finish.

Reads Claude Code session transcripts through the shared reader (lib/transcript_reader.py): every
subagents/agent-*.jsonl that has a sibling agent-*.meta.json, under --root, else under the projects
directory of each local source the sources file lists (lib/transcript_sources.py; with no
--sources-file, the local configuration directory). A turn is counted in the unit `maxTurns` uses (see
plugins/discovery/reference/parent-contract.md): one assistant message, however
many parallel tool calls it holds, so assistant records are grouped by
message.id and the distinct ids are counted.

A local source whose projects directory exists but cannot be listed is a gap: the report header
(transcript_sources.lookup_report, `header` in --json) names it with its retry, this invocation
verbatim, and --diagnostics-dir writes it there as a lookup diagnostics record. The header also
names each source of the sources file on another host, which this script does not read, so its
counts are this host's only. With --root it reads that one directory and has no header.

Only counts, dates and agent types are printed, never transcript content. The markdown is
published output: it passes through the publish redactor (lib/publish.py over --sources-file and
--redact-identifiers), and when that fails closed nothing is printed and the exit is 2; --json is not.

Exit 0 = report written (an empty result is still a report)
Exit 2 = the --root cannot be read, the sources file is malformed, the publish redactor fails
         closed, or a usage error

Usage:
  python3 turns-to-complete.py [--root DIR] [--agent-type A,B] [--since YYYY-MM-DD]
                               [--ceiling N] [--json] [--sources-file F]
                               [--redact-identifiers LIST] [--diagnostics-dir DIR]

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

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
sys.dont_write_bytecode = True

import publish  # noqa: E402  (the generated shared copy in ../lib)
import transcript_reader  # noqa: E402  (the generated shared copy in ../lib)
import transcript_sources  # noqa: E402  (the generated shared copy in ../lib)

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
        for rec in transcript_reader.iter_records(jsonl):
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
    except OSError:
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
    ap.add_argument("--root", help="one transcripts root; default: each local source's projects directory")
    ap.add_argument(
        "--agent-type", default=DEFAULT_TYPES, help="comma-separated agentType filter"
    )
    ap.add_argument("--since", type=date.fromisoformat, metavar="YYYY-MM-DD")
    ap.add_argument("--ceiling", type=int, default=40, help="turn ceiling (default 40)")
    ap.add_argument("--json", action="store_true", help="emit JSON instead of markdown")
    ap.add_argument("--sources-file", default="", help="a transcript sources file, whose identifiers markdown redacts")
    ap.add_argument("--redact-identifiers", default="", help="comma-separated names and paths markdown also redacts")
    ap.add_argument("--diagnostics-dir", help="write a lookup gap here as a diagnostics record")
    args = ap.parse_args()

    sources = None
    header: list[str] = []
    if args.root:
        roots = [Path(args.root).expanduser()]
        try:
            list(os.scandir(roots[0]))
        except OSError as exc:
            print(f"error: cannot read root {roots[0]}: {exc.strerror}", file=sys.stderr)
            return 2
    else:
        try:
            report = transcript_sources.lookup_report(
                args.sources_file, transcript_sources.retry_argv(__file__, sys.argv[1:]), args.diagnostics_dir,
            )
        except transcript_sources.SourcesError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 2
        sources = report.sources
        unread = {gap.source for gap in report.gaps}
        roots = [Path(e.config_dir) / "projects" for e in sources.local() if e.name not in unread]
        header = report.header + [
            f"Not read by this skill: {entry.name} (remote; this skill reads this host's sources only)"
            for entry in sources.all() if not entry.is_local
        ]

    wanted = {t.strip() for t in args.agent_type.split(",") if t.strip()}
    since = args.since.isoformat() if args.since else None
    rows: list[dict] = []
    skipped = 0
    unfinished = 0
    for dirpath, _, files in (walked for root in roots for walked in os.walk(root)):
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
        print(json.dumps({"header": header, "dispatches": rows, "summary": summary}, indent=2))
        return 0
    try:
        publisher = publish.publisher(args.sources_file, args.redact_identifiers, sources=sources)
    except publish.PublishError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    dispatches = (
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
    cols = ("agentType", "n", "min", "p50", "p90", "max", "at_ceiling")
    totals = table(list(cols), [[s[k] for k in cols] for s in summary])
    lead = "\n".join(transcript_sources.report_header_md(header)) + ("\n" if header else "")
    print(publisher.redact(f"{lead}{dispatches}\n\n{totals}"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
