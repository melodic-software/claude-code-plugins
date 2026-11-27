#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Read per-subagent dispatch turn rows from the audit-sessions store.

    dispatches.py --data-dir D [--sources-file F] [--agent-type A,B]
                  [--since YYYY-MM-DD] [--ceiling N]

Reads only the `session-record/v2` files `collect.py` wrote, across every source's
partition; it never opens a transcript. Prints one `audit-sessions.dispatches/v1`
JSON envelope on stdout:

- `data.header`: collection gaps and stale/uncollected sources from
  `transcript_sources.store_header`, plus one `Not read by this skill:` line for
  each source holding stored records that lack `subagents.dispatches` (older or
  carried-over records, kept readable rather than dropped silently).
- `data.dispatches`: completed dispatches matching `--agent-type` (when given)
  and `--since`, sorted by `(date, agentType)`, each with `agentType`, `complete`,
  `date`, `turns`, `hit_ceiling`, `resumed` and `source`.
- `data.unfinished`: matching dispatches below `--ceiling` with no final
  `stop_reason` (or `tool_use`).
- `data.sessions_read` and `data.sessions_missing_dispatches`.

Exit 0 = pass, 2 = error (bad arguments, malformed sources file, unreadable or
wrong-schema store record), 3 = no store under `--data-dir`. Stdlib only; Python 3.10+.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from datetime import date
from pathlib import Path

_SCRIPTS = str(Path(__file__).resolve().parent)
if _SCRIPTS not in sys.path:
    sys.path.insert(0, _SCRIPTS)

import census  # noqa: E402  (beside this script)
import transcript_sources  # noqa: E402  (beside this script)

SCHEMA = "audit-sessions.dispatches/v1"


def _emit(status: str, summary: str, data: dict, code: int) -> int:
    print(json.dumps({"schema": SCHEMA, "status": status, "summary": summary, "data": data}, indent=2))
    return code


def _source_name(record: dict) -> str:
    prov = record.get("provenance")
    source = prov.get("source") if isinstance(prov, dict) else None
    return source if isinstance(source, str) and source else "unknown"


def collect_dispatches(
    records: list[dict],
    *,
    wanted: set[str] | None,
    since: str | None,
    ceiling: int,
) -> tuple[list[dict], int, dict[str, int]]:
    """Extract dispatch rows, unfinished count and per-source count of records lacking `subagents.dispatches`."""
    rows: list[dict] = []
    unfinished = 0
    missing_by_source: Counter[str] = Counter()
    for record in records:
        source = _source_name(record)
        sub = record.get("subagents")
        raw_dispatches = sub.get("dispatches") if isinstance(sub, dict) else None
        if not isinstance(raw_dispatches, list):
            missing_by_source[source] += 1
            continue
        for item in raw_dispatches:
            if not isinstance(item, dict):
                continue
            agent = item.get("agent_type")
            if not isinstance(agent, str) or not agent:
                continue
            if wanted and agent not in wanted:
                continue
            day = item.get("date") if isinstance(item.get("date"), str) else "unknown"
            if since and not (day[:1].isdigit() and day >= since):
                continue
            raw_turns = item.get("turns")
            turns = raw_turns if isinstance(raw_turns, int) and not isinstance(raw_turns, bool) else 0
            hit_max = bool(item.get("hit_max_turns"))
            last_stop = item.get("last_stop_reason") if isinstance(item.get("last_stop_reason"), str) else None
            resumed_after = item.get("resumed_after_turn")
            resumed_max = bool(item.get("resumed_after_max_turns"))
            hit = turns >= ceiling or hit_max
            complete = hit or last_stop not in (None, "tool_use")
            if not complete:
                unfinished += 1
                continue
            was_resumed = (
                isinstance(resumed_after, int) and not isinstance(resumed_after, bool) and resumed_after >= ceiling
            ) or resumed_max
            rows.append(
                {
                    "agentType": agent,
                    "complete": True,
                    "date": day,
                    "turns": turns,
                    "hit_ceiling": hit,
                    "resumed": ("yes" if was_resumed else "unknown") if hit else "n/a",
                    "source": source,
                }
            )
    rows.sort(key=lambda r: (r["date"], r["agentType"], r["source"]))
    return rows, unfinished, dict(sorted(missing_by_source.items()))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Read per-subagent dispatch turn rows from the audit-sessions store.")
    parser.add_argument("--data-dir", required=True, help="session-flow plugin data directory holding the store")
    parser.add_argument("--sources-file", default="", help="optional transcript sources file for store header checks")
    parser.add_argument("--agent-type", default="", help="optional comma-separated agentType filter")
    parser.add_argument("--since", type=date.fromisoformat, metavar="YYYY-MM-DD", help="dispatches on or after this UTC date")
    parser.add_argument("--ceiling", type=int, default=40, help="turn ceiling (default 40)")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    try:
        args = parser.parse_args(argv)
    except SystemExit as exc:
        if exc.code == 0:
            raise
        return _emit("error", "bad arguments", {}, 2)

    sources = None
    if args.sources_file:
        try:
            sources = transcript_sources.load(args.sources_file)
        except transcript_sources.SourcesError as exc:
            return _emit("error", f"sources file not usable: {exc}", {}, 2)
        for warning in sources.warnings:
            print(warning, file=sys.stderr)

    data_dir = Path(args.data_dir)
    store = census.store_dir(data_dir)
    if not store.is_dir():
        return _emit("error", f"no audit-sessions store under {data_dir}; run collect first", {}, 3)

    try:
        records, skipped = census.load_records(data_dir)
    except OSError as exc:
        return _emit("error", str(exc), {}, 2)
    if skipped:
        return _emit("error", f"{skipped} store files unreadable or not {census.RECORD_SCHEMA}; re-run collect", {}, 2)

    wanted = {t.strip() for t in args.agent_type.split(",") if t.strip()} or None
    since = args.since.isoformat() if args.since else None
    rows, unfinished, missing = collect_dispatches(records, wanted=wanted, since=since, ceiling=args.ceiling)

    header = transcript_sources.store_header(store, sources)
    for source, count in missing.items():
        header.append(
            f"Not read by this skill: {source} ({count} stored session record(s) lack per-dispatch rows; "
            "re-run collect for present transcripts)"
        )

    data = {
        "header": header,
        "dispatches": rows,
        "unfinished": unfinished,
        "sessions_read": len(records) - sum(missing.values()),
        "sessions_missing_dispatches": missing,
    }
    return _emit("pass", f"{len(rows)} completed dispatch(es) from {len(records)} session(s)", data, 0)


if __name__ == "__main__":
    sys.exit(main())
