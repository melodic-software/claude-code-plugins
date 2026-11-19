#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Context at the 10th assistant message of sessions resumed from a handoff, by session-flow plugin version.

    resumed_context.py [--projects-root DIR] [--cwd-prefix PREFIX ...] [--since YYYY-MM-DD]
                       [--until YYYY-MM-DD] [--baseline VERSION --candidate VERSION]
                       [--min-per-side N] [--format json|md]

Unlike sweep.py this reads transcripts, through the shared transcript_reader, because the store
keeps no per-message context. It reads each main transcript `<root>/<project>/<session>.jsonl`
(never a subagent's, never a `.orphaned-` copy) and writes nothing.

- A session is resumed when one of its first 3 typed turns holds a `Read @<path>/handoffs/<file>.md`
  directive, the line a handoff's resume prompt opens with.
- Context at a message is input + cache-read + cache-creation tokens of one main-chain assistant
  message, keyed by `message.id` with the largest of its streaming records kept. Sidechain records
  and messages whose context is 0 are skipped. `ctx_msg10` is the 10th such message after the
  resume turn, null when the session has fewer.
- The plugin version is read from a `plugins/cache/<marketplace>/session-flow/<version>` path in
  the transcript: the last one at or before the resume turn, else the first after it, else
  `unknown`. `plugin_versions_seen` counts the distinct versions in the part of the transcript read.
- `--cwd-prefix` keeps a session whose first working directory, or whose handoff path, starts with
  any prefix given (plain string prefix); with none, every project is read. A session with neither
  is counted as unattributed. `--since`/`--until` filter on the session's first timestamp (UTC day).
- Sessions whose entrypoints are all Agent SDK ones (`census.AUTOMATED_ENTRYPOINTS`) are set aside
  and counted.

Prints one JSON envelope (schema `audit-sessions.resumed-context/v1`) or markdown. `overall` holds
the median and n over every version, the figure a date-window comparison reads. `groups` holds,
per plugin version, the median `ctx_msg10` and `n` over the sessions that reached 10 messages, and
`sufficient` (n >= --min-per-side). `--baseline` and `--candidate` add `comparison`: both sides'
median and n, `rise` (candidate median above baseline; null unless both sides are sufficient), and
`miss_count` null, the slot a retro or the owner fills with missed binding items.
Exit 0 pass, 1 warning (a compared side is short of --min-per-side), 2 error. Stdlib only; Python 3.10+.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import statistics
import sys
from datetime import date
from pathlib import Path

_PLUGIN_SCRIPTS = str(Path(__file__).resolve().parents[3] / "scripts")
if _PLUGIN_SCRIPTS not in sys.path:
    sys.path.insert(0, _PLUGIN_SCRIPTS)

import census  # noqa: E402  (plugin-level scripts/census.py)
import transcript_reader  # noqa: E402  (plugin-level scripts/transcript_reader.py)

SCHEMA = "audit-sessions.resumed-context/v1"
MESSAGE_INDEX = 10
RESUME_TURNS = 3
DEFAULT_MIN_PER_SIDE = 10
RESUME_RE = re.compile(r"Read @([^\s`\"']*handoffs/[^\s`\"',]+\.md)")
VERSION_RE = re.compile(r"plugins[/\\]+cache[/\\]+[\w.-]+[/\\]+session-flow[/\\]+(\d[\w.+-]*)")
UNKNOWN = "unknown"


def _count(value: object) -> int:
    return value if isinstance(value, int) and not isinstance(value, bool) else 0


def context_tokens(usage: dict) -> int:
    return sum(_count(usage.get(k)) for k in ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"))


def default_projects_root() -> Path:
    config_dir = os.environ.get("CLAUDE_CONFIG_DIR")
    return (Path(config_dir) if config_dir else Path.home() / ".claude") / "projects"


def read_session(path: Path) -> dict:
    """One pass over a transcript, stopping once the 10th message and the version are settled."""
    start = cwd = handoff = None
    entrypoints: set[str] = set()
    versions: list[str] = []
    version_at_resume = version_after = None
    typed = 0
    resumed = False
    ctx: dict[str, int] = {}
    order: list[str] = []
    records = transcript_reader.iter_records(path)
    try:
        for index, record in enumerate(records):
            if start is None and isinstance(record.get("timestamp"), str):
                start = record["timestamp"]
            if cwd is None and isinstance(record.get("cwd"), str) and record["cwd"]:
                cwd = record["cwd"]
            if isinstance(record.get("entrypoint"), str):
                entrypoints.add(record["entrypoint"])
            match = VERSION_RE.search(json.dumps(record))
            if match:
                if match.group(1) not in versions:
                    versions.append(match.group(1))
                if not resumed:
                    version_at_resume = match.group(1)
                elif version_after is None:
                    version_after = match.group(1)
            if record.get("isSidechain"):
                continue
            kind = record.get("type")
            if kind == "user" and not resumed and (text := transcript_reader.typed_text(record)) is not None:
                typed += 1
                found = RESUME_RE.search(text)
                if found:
                    resumed, handoff = True, found.group(1)
                elif typed >= RESUME_TURNS:
                    break
            elif kind == "assistant" and resumed:
                message = record.get("message") if isinstance(record.get("message"), dict) else {}
                usage = message.get("usage")
                key = message.get("id") if isinstance(message.get("id"), str) else f"line-{index}"
                if key not in ctx:
                    usable = [k for k in order if ctx[k] > 0]
                    if len(usable) >= MESSAGE_INDEX and (version_at_resume or version_after):
                        break
                    ctx[key] = 0
                    order.append(key)
                if isinstance(usage, dict):
                    ctx[key] = max(ctx[key], context_tokens(usage))
    finally:
        records.close()
    usable = [ctx[k] for k in order if ctx[k] > 0]
    return {
        "session_id": path.stem,
        "project": path.parent.name,
        "start": start,
        "cwd": cwd,
        "entrypoints": sorted(entrypoints),
        "resumed": resumed,
        "handoff_path": handoff,
        "handoff": Path(handoff).name if handoff else None,
        "plugin_version": version_at_resume or version_after or UNKNOWN,
        "plugin_versions_seen": len(versions),
        "ctx_msg10": usable[MESSAGE_INDEX - 1] if len(usable) >= MESSAGE_INDEX else None,
    }


def in_window(start: str | None, since: date | None, until: date | None) -> bool:
    if since is None and until is None:
        return True
    try:
        day = date.fromisoformat(start[:10])  # type: ignore[index]
    except (TypeError, ValueError):
        return False
    return (since is None or day >= since) and (until is None or day <= until)


def transcripts(root: Path, since: date | None) -> list[Path]:
    """Main transcripts, less any last written before `since`: such a session cannot start after it."""
    floor = None
    if since is not None:
        floor = census.epoch(f"{since.isoformat()}T00:00:00Z")
    paths = []
    for path in sorted(root.glob("*/*.jsonl")):
        if ".orphaned-" in path.name:
            continue
        if floor is not None and path.stat().st_mtime < floor:
            continue
        paths.append(path)
    return paths


def side(groups: dict[str, list[int]], version: str, minimum: int) -> dict:
    values = groups.get(version, [])
    return {
        "plugin_version": version,
        "n": len(values),
        "median": statistics.median(values) if values else None,
        "sufficient": len(values) >= minimum,
    }


def build_data(rows: list[dict], counts: dict, args: argparse.Namespace) -> dict:
    groups: dict[str, list[int]] = {}
    for row in rows:
        if row["ctx_msg10"] is not None:
            groups.setdefault(row["plugin_version"], []).append(row["ctx_msg10"])
    order = sorted(groups, key=lambda v: (v == UNKNOWN, census.version_key(v) if v != UNKNOWN else ()))
    values = [v for vs in groups.values() for v in vs]
    data = {
        "method": f"context at the {MESSAGE_INDEX}th main-chain assistant message after a handoff resume",
        "scope": {"cwd_prefixes": args.cwd_prefix or []},
        "window": {"since": args.since and args.since.isoformat(), "until": args.until and args.until.isoformat()},
        "min_per_side": args.min_per_side,
        "counts": counts,
        "overall": {"n": len(values), "median": statistics.median(values) if values else None},
        "groups": [side(groups, v, args.min_per_side) for v in order],
        "sessions": rows,
    }
    if args.baseline is not None:
        before = side(groups, args.baseline, args.min_per_side)
        after = side(groups, args.candidate, args.min_per_side)
        rise = after["median"] > before["median"] if before["sufficient"] and after["sufficient"] else None
        data["comparison"] = {"baseline": before, "candidate": after, "rise": rise, "miss_count": None}
    return data


def _fmt(value: object) -> str:
    if value is None:
        return "n/a"
    if isinstance(value, bool):
        return "yes" if value else "no"
    return f"{value:,.0f}" if isinstance(value, (int, float)) else str(value)


def render_md(data: dict) -> str:
    c = data["counts"]
    lines = [
        "# Context at the 10th resumed message",
        "",
        f"Transcripts read: {c['transcripts']}; in scope: {c['in_scope']}; resumed from a handoff: {c['resumed']};"
        f" reached {MESSAGE_INDEX} messages: {c['reached_10']}; unattributed: {c['unattributed']};"
        f" automated set aside: {c['automated_set_aside']}.",
        "",
        f"All versions: median {_fmt(data['overall']['median'])} tokens, n {data['overall']['n']}.",
        "",
        "| Plugin version | Median context (tokens) | n | Sufficient |",
        "|---|---|---|---|",
    ]
    lines += [f"| `{g['plugin_version']}` | {_fmt(g['median'])} | {g['n']} | {_fmt(g['sufficient'])} |" for g in data["groups"]]
    comparison = data.get("comparison")
    if comparison:
        b, a = comparison["baseline"], comparison["candidate"]
        lines += [
            "",
            "## Comparison",
            "",
            f"- Baseline `{b['plugin_version']}`: median {_fmt(b['median'])}, n {b['n']}",
            f"- Candidate `{a['plugin_version']}`: median {_fmt(a['median'])}, n {a['n']}",
            f"- Rise: {_fmt(comparison['rise'])}"
            + (f" (decided once both sides reach {data['min_per_side']})" if comparison["rise"] is None else ""),
            "- Miss count: to be filled by a retro or the owner",
        ]
    return "\n".join(lines) + "\n"


def emit(fmt: str, status: str, summary: str, data: dict, code: int) -> int:
    if fmt == "md" and status != "error":
        sys.stdout.write(render_md(data))
    else:
        print(json.dumps({"schema": SCHEMA, "status": status, "summary": summary, "data": data}, indent=2))
    return code


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Context at the 10th resumed message, by session-flow plugin version.")
    parser.add_argument("--projects-root", type=Path, default=None)
    parser.add_argument("--cwd-prefix", nargs="+", action="extend", help="keep sessions whose cwd or handoff path starts with one")
    parser.add_argument("--since", type=date.fromisoformat)
    parser.add_argument("--until", type=date.fromisoformat)
    parser.add_argument("--baseline", help="plugin version before the change")
    parser.add_argument("--candidate", help="plugin version after the change")
    parser.add_argument("--min-per-side", type=census._positive, default=DEFAULT_MIN_PER_SIDE)
    parser.add_argument("--format", choices=("json", "md"), default="json")
    try:
        args = parser.parse_args(argv)
    except SystemExit as exc:
        if exc.code == 0:
            raise
        return emit("json", "error", "bad arguments", {}, 2)
    if (args.baseline is None) != (args.candidate is None):
        return emit("json", "error", "--baseline and --candidate go together", {}, 2)
    root = args.projects_root or default_projects_root()
    if not root.is_dir():
        return emit("json", "error", f"projects root {root} is not a directory", {}, 2)
    prefixes = tuple(args.cwd_prefix or ())
    counts = {"transcripts": 0, "in_scope": 0, "unattributed": 0, "automated_set_aside": 0, "resumed": 0, "reached_10": 0, "unreadable": 0}
    rows = []
    for path in transcripts(root, args.since):
        counts["transcripts"] += 1
        try:
            row = read_session(path)
        except OSError as exc:
            counts["unreadable"] += 1
            print(f"resumed_context.py: skipped unreadable transcript {path}: {exc!r}", file=sys.stderr)
            continue
        if not in_window(row["start"], args.since, args.until):
            continue
        if prefixes:
            places = [p for p in (row["cwd"], row["handoff_path"]) if p]
            if not places:
                counts["unattributed"] += 1
                continue
            if not any(p.startswith(prefixes) for p in places):
                continue
        if row["entrypoints"] and all(e in census.AUTOMATED_ENTRYPOINTS for e in row["entrypoints"]):
            counts["automated_set_aside"] += 1
            continue
        counts["in_scope"] += 1
        if row["resumed"]:
            counts["resumed"] += 1
            counts["reached_10"] += row["ctx_msg10"] is not None
            rows.append(row)
    data = build_data(rows, counts, args)
    summary = f"{counts['reached_10']} of {counts['resumed']} resumed sessions reached {MESSAGE_INDEX} messages"
    status, code = "pass", 0
    comparison = data.get("comparison")
    if comparison and not (comparison["baseline"]["sufficient"] and comparison["candidate"]["sufficient"]):
        status, code = "warning", 1
        summary += f"; a compared side has fewer than {args.min_per_side} sessions"
    return emit(args.format, status, summary, data, code)


if __name__ == "__main__":
    sys.exit(main())
