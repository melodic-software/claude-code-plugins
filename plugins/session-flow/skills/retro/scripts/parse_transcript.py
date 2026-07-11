#!/usr/bin/env python3
"""Parse Claude Code JSONL transcript(s) and extract quantitative metrics.

Zero external dependencies — stdlib only.

Usage (single-session, backward compatible):
    python parse_transcript.py <session_id> <base_path>

Usage (multi-session, new):
    python parse_transcript.py --sessions <sid1> <sid2> ... --base <base_path>
    python parse_transcript.py --chain-from <handoff-file> --base <base_path>

Arguments:
    session_id    Single UUID session identifier (positional, backward compat)
    base_path     Base directory containing session JSONL files (positional)
    --sessions    Multiple UUIDs to parse + aggregate (first = current, rest = chained prior)
    --chain-from  Walk session chain via handoff frontmatter (previous_handoff / previous_session_id)
                  starting from the given handoff journal entry file; emits aggregated multi-session output
    --base        Base directory containing session JSONL files (required with --sessions / --chain-from)
    --help        Print help and exit 0

Output:
    JSON to stdout.

    Single-session shape (existing — preserved):
        {"status": "...", "summary": "...", "data": {...}}

    Multi-session shape:
        {
          "status": "...",
          "summary": "...",
          "sessions": [
            {"id": "<UUID>", "role": "current"|"previous",
             "transcript_present": true|false, "subagents_present": true|false,
             "data": {...},  # or "error": "..." when transcript missing
            },
            ...
          ],
          "aggregate": {
            "total_assistant_turns": N, "total_human_messages": N,
            "total_input_tokens": N, "total_output_tokens": N,
            "total_compactions": N, "total_tool_rejections": N,
            "all_tools": {"ToolName": count, ...},
            "all_subagents": [{"id", "type", "description", "session_id"}, ...],
            "all_models": [...], "all_branches": [...],
          },
        }

Exit codes:
    0 = success (or partial chain — some SIDs missing transcripts, but at
        least one transcript or subagent record found)
    1 = warnings (e.g., no transcript found for the only SID but subagents exist)
    2 = error (e.g., invalid arguments, no files at all — including a
        multi-session parse where every SID resolves to nothing)
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Any, NoReturn, cast


def parse_timestamp(ts_str: str) -> datetime | None:
    """Parse ISO 8601 timestamp string to datetime."""
    if not ts_str:
        return None
    try:
        return datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return None


# Tools whose `input.file_path` is a write target. Read/Grep/Glob also have
# file_path inputs but should not count as "files modified".
_FILE_MODIFYING_TOOLS = frozenset({"Write", "Edit", "NotebookEdit"})

# Truncation length for tool-rejection error snippets in the output.
_REJECTION_SNIPPET_LEN = 200


def _normalize_path(path: str, cwd: str | None) -> str:
    """Strip cwd prefix from absolute paths so relative and absolute references dedup."""
    if not path:
        return path

    norm_path = path.replace("\\", "/").rstrip("/")

    if not cwd:
        return norm_path

    norm_cwd = cwd.replace("\\", "/").rstrip("/")
    if not norm_cwd:
        return norm_path

    if norm_path == norm_cwd:
        return "."

    prefix = norm_cwd + "/"
    if norm_path.startswith(prefix):
        return norm_path[len(prefix) :]

    return norm_path


def _as_dict(value: Any) -> dict[str, Any]:
    """Return value as a dict when it is one, else an empty dict."""
    return cast(dict[str, Any], value) if isinstance(value, dict) else {}


def _as_list(value: Any) -> list[Any]:
    """Return value as a list when it is one, else an empty list."""
    return cast(list[Any], value) if isinstance(value, list) else []


def _count_tools_and_extract_paths(content: list[Any], metrics: dict[str, Any]) -> None:
    """Single-pass: count tool uses and extract file paths from Write/Edit."""
    for raw_item in content:
        if not isinstance(raw_item, dict):
            continue
        item = cast(dict[str, Any], raw_item)
        if item.get("type") != "tool_use":
            continue
        name = str(item.get("name", "unknown"))
        metrics["tool_usage"][name] += 1
        if name in _FILE_MODIFYING_TOOLS:
            fp_candidate = _as_dict(item.get("input")).get("file_path")
            if isinstance(fp_candidate, str) and fp_candidate:
                metrics["files_modified"].add(fp_candidate)


def parse_main_transcript(filepath: Path) -> dict[str, Any] | None:
    """Stream-parse main JSONL transcript and collect metrics."""
    metrics: dict[str, Any] = {
        "assistant_turns": 0,
        "user_turns": 0,
        "human_messages": 0,
        "tool_result_messages": 0,
        "tool_usage": Counter(),
        "tool_rejections": [],
        "compactions": [],
        "assistant_timestamps": [],
        "turn_durations_ms": [],
        "hook_summaries": [],
        "errors": [],
        "first_timestamp": None,
        "last_timestamp": None,
        "models": set(),
        "stop_reasons": Counter(),
        "git_branches": set(),
        "versions": set(),
        "files_modified": set(),
        "cwd": None,
        "total_input_tokens": 0,
        "total_output_tokens": 0,
        "cache_creation_tokens": 0,
        "cache_read_tokens": 0,
        "queued_messages": 0,
    }

    if not filepath.is_file():
        return None

    with filepath.open(encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                loaded = json.loads(line)
            except json.JSONDecodeError:
                metrics["errors"].append(
                    {
                        "type": "parse_error",
                        "detail": "Malformed JSON line",
                    }
                )
                continue

            if not isinstance(loaded, dict):
                continue

            event = cast(dict[str, Any], loaded)
            timestamp = event.get("timestamp")
            if isinstance(timestamp, str) and timestamp:
                if metrics["first_timestamp"] is None:
                    metrics["first_timestamp"] = timestamp
                metrics["last_timestamp"] = timestamp

            if branch := event.get("gitBranch"):
                metrics["git_branches"].add(branch)
            if version := event.get("version"):
                metrics["versions"].add(version)
            if metrics["cwd"] is None and (cwd := event.get("cwd")):
                # First cwd is session context; mid-session directory changes are ignored.
                metrics["cwd"] = cwd

            match event.get("type"):
                case "assistant":
                    metrics["assistant_turns"] += 1
                    msg = _as_dict(event.get("message"))

                    if isinstance(timestamp, str) and timestamp:
                        metrics["assistant_timestamps"].append(timestamp)

                    if model := msg.get("model"):
                        metrics["models"].add(model)

                    if stop := msg.get("stop_reason"):
                        metrics["stop_reasons"][stop] += 1

                    usage = _as_dict(msg.get("usage"))
                    metrics["total_input_tokens"] += usage.get("input_tokens", 0)
                    metrics["total_output_tokens"] += usage.get("output_tokens", 0)
                    metrics["cache_creation_tokens"] += usage.get(
                        "cache_creation_input_tokens", 0
                    )
                    metrics["cache_read_tokens"] += usage.get(
                        "cache_read_input_tokens", 0
                    )

                    _count_tools_and_extract_paths(
                        _as_list(msg.get("content")), metrics
                    )

                case "user":
                    metrics["user_turns"] += 1
                    content_raw = _as_dict(event.get("message")).get("content", [])

                    if isinstance(content_raw, str):
                        metrics["human_messages"] += 1
                        continue

                    for raw_item in _as_list(content_raw):
                        if isinstance(raw_item, str):
                            metrics["human_messages"] += 1
                            continue
                        if not isinstance(raw_item, dict):
                            continue
                        item = cast(dict[str, Any], raw_item)
                        match item.get("type"):
                            case "tool_result":
                                metrics["tool_result_messages"] += 1
                                if item.get("is_error"):
                                    metrics["tool_rejections"].append(
                                        {
                                            "tool_use_id": item.get("tool_use_id", ""),
                                            "snippet": str(item.get("content", ""))[
                                                :_REJECTION_SNIPPET_LEN
                                            ],
                                        }
                                    )
                            case "text":
                                metrics["human_messages"] += 1
                            case _:
                                continue

                case "system":
                    match event.get("subtype", ""):
                        case "compact_boundary":
                            compact_meta = event.get("compactMetadata", {})
                            metrics["compactions"].append(
                                {
                                    "timestamp": timestamp,
                                    "trigger": compact_meta.get("trigger", "unknown"),
                                    "pre_tokens": compact_meta.get("preTokens", 0),
                                }
                            )

                        case "stop_hook_summary":
                            metrics["hook_summaries"].append(
                                {
                                    "hook_count": event.get("hookCount", 0),
                                    "prevented_continuation": event.get(
                                        "preventedContinuation", False
                                    ),
                                    "has_output": event.get("hasOutput", False),
                                    "hook_errors": event.get("hookErrors", []),
                                }
                            )
                        case _:
                            pass

                case "queue-operation":
                    if event.get("operation") == "enqueue":
                        metrics["queued_messages"] += 1

                case "file-history-snapshot":
                    backups = _as_dict(
                        _as_dict(event.get("snapshot")).get("trackedFileBackups")
                    )
                    for fpath_key in backups:
                        metrics["files_modified"].add(str(fpath_key))

                case _:
                    pass

    metrics["files_modified"] = {
        _normalize_path(p, metrics["cwd"]) for p in metrics["files_modified"]
    }

    metrics["turn_durations_ms"] = _compute_turn_deltas_ms(
        metrics["assistant_timestamps"]
    )

    return metrics


def _compute_turn_deltas_ms(timestamps: list[str]) -> list[int]:
    """Wall-clock deltas between consecutive assistant events in milliseconds.

    CC's system.turn_duration events are emitted sparsely (1-5 per session)
    and don't reflect every assistant turn. Deriving from assistant-event
    timestamps gives one delta per turn-pair (N-1 deltas for N turns) and
    measures end-to-end cycle time (user wait + tool exec + agent thinking).
    """
    deltas: list[int] = []
    prev: datetime | None = None
    for ts in timestamps:
        cur = parse_timestamp(ts)
        if cur is None:
            continue
        if prev is not None:
            delta_ms = round((cur - prev).total_seconds() * 1000)
            if delta_ms >= 0:
                deltas.append(delta_ms)
        prev = cur
    return deltas


def parse_subagents(subagent_dir: Path) -> list[dict[str, str]]:
    """Parse subagent meta files for inventory."""
    if not subagent_dir.is_dir():
        return []

    subagents: list[dict[str, str]] = []
    for meta_file in sorted(subagent_dir.glob("*.meta.json")):
        try:
            meta = json.loads(meta_file.read_text(encoding="utf-8", errors="replace"))
            agent_id = meta_file.stem.replace(".meta", "")
            subagents.append(
                {
                    "id": agent_id,
                    "type": meta.get("agentType", "unknown"),
                    "description": meta.get("description", ""),
                }
            )
        except (json.JSONDecodeError, OSError):
            continue

    return subagents


def compute_duration_stats(durations_ms: list[int]) -> dict[str, int]:
    """Compute stats from a list of durations in milliseconds."""
    if not durations_ms:
        return {
            "count": 0,
            "avg_ms": 0,
            "min_ms": 0,
            "max_ms": 0,
            "total_ms": 0,
        }
    total = sum(durations_ms)
    return {
        "count": len(durations_ms),
        "avg_ms": round(total / len(durations_ms)),
        "min_ms": min(durations_ms),
        "max_ms": max(durations_ms),
        "total_ms": total,
    }


def compute_session_duration(
    first_ts: str | None,
    last_ts: str | None,
) -> dict[str, str | float | None]:
    """Compute session duration from first and last timestamp strings."""
    if not first_ts or not last_ts:
        return {"start": None, "end": None, "duration_minutes": 0}

    start = parse_timestamp(first_ts)
    end = parse_timestamp(last_ts)

    if not start or not end:
        return {"start": None, "end": None, "duration_minutes": 0}

    duration = (end - start).total_seconds() / 60.0

    return {
        "start": start.isoformat(),
        "end": end.isoformat(),
        "duration_minutes": round(duration, 1),
    }


def _emit_and_exit(
    status: str, summary: str, data: dict[str, Any], code: int
) -> NoReturn:
    print(json.dumps({"status": status, "summary": summary, "data": data}))
    sys.exit(code)


def build_session_data(
    session_id: str, metrics: dict[str, Any], subagents: list[dict[str, Any]]
) -> dict[str, Any]:
    """Convert parsed metrics + subagents into the `data` block emitted in single-session
    output AND embedded per-session in multi-session output."""
    session_duration = compute_session_duration(
        metrics["first_timestamp"], metrics["last_timestamp"]
    )
    turn_stats = compute_duration_stats(metrics["turn_durations_ms"])
    return {
        "session": {
            "id": session_id,
            "start": session_duration["start"],
            "end": session_duration["end"],
            "duration_minutes": session_duration["duration_minutes"],
            "models": sorted(metrics["models"]),
            "versions": sorted(metrics["versions"]),
            "git_branches": sorted(metrics["git_branches"]),
        },
        "turns": {
            "assistant": metrics["assistant_turns"],
            "user": metrics["user_turns"],
            "human_messages": metrics["human_messages"],
            "tool_result_messages": metrics["tool_result_messages"],
        },
        "tokens": {
            "total_input": metrics["total_input_tokens"],
            "total_output": metrics["total_output_tokens"],
            "cache_creation": metrics["cache_creation_tokens"],
            "cache_read": metrics["cache_read_tokens"],
            "total_context": (
                metrics["total_input_tokens"]
                + metrics["cache_creation_tokens"]
                + metrics["cache_read_tokens"]
            ),
        },
        "queued_user_messages": metrics["queued_messages"],
        "tools": {
            "usage": dict(metrics["tool_usage"].most_common()),
            "rejections": metrics["tool_rejections"],
            "rejection_count": len(metrics["tool_rejections"]),
        },
        "compactions": {
            "count": len(metrics["compactions"]),
            "details": metrics["compactions"],
        },
        "turn_durations": turn_stats,
        "stop_reasons": dict(metrics["stop_reasons"]),
        "hook_summaries": {
            "count": len(metrics["hook_summaries"]),
            "prevented_continuations": sum(
                1 for h in metrics["hook_summaries"] if h["prevented_continuation"]
            ),
            "hook_errors": sum(
                len(h["hook_errors"]) for h in metrics["hook_summaries"]
            ),
        },
        "files_modified": sorted(metrics["files_modified"]),
        "subagents": subagents,
        "errors": metrics["errors"],
    }


def parse_one_session(session_id: str, base_path: Path) -> dict[str, Any]:
    """Parse a single session's transcript + subagents. Returns either a fully
    populated `data` block per build_session_data() OR an error stub
    {"transcript_present": False, ...}."""
    main_jsonl = base_path / f"{session_id}.jsonl"
    subagent_dir = base_path / session_id / "subagents"

    metrics = parse_main_transcript(main_jsonl)
    subagents = parse_subagents(subagent_dir)

    if metrics is None:
        return {
            "id": session_id,
            "transcript_present": False,
            "subagents_present": bool(subagents),
            "subagents": subagents,
            "error": f"No transcript found at {main_jsonl}",
        }

    data = build_session_data(session_id, metrics, subagents)
    return {
        "id": session_id,
        "transcript_present": True,
        "subagents_present": bool(subagents),
        "data": data,
    }


def extract_chain_from_handoff(
    handoff_file: Path, base_path: Path, limit: int = 10
) -> list[str]:
    """Walk handoff journal-entry chain backwards via previous_handoff / previous_session_id
    frontmatter fields. Returns ordered list of session-ids (current handoff's session_id
    first, then prior). NOTE: callers separately prepend the current $CLAUDE_CODE_SESSION_ID
    if they want it; this function only walks the chain starting from the given file.

    Forward-only convention: older entries lacking session_id break the walk cleanly."""
    sids: list[str] = []
    seen: set[str] = set()
    cursor: Path | None = handoff_file
    depth = 0

    while cursor and cursor.is_file() and depth < limit:

        sid = None
        prev_handoff_rel = None
        try:
            with cursor.open(encoding="utf-8", errors="replace") as f:
                # Read only the frontmatter (first --- block).
                in_fm = False
                for line in f:
                    line = line.rstrip("\n")
                    if line == "---":
                        if not in_fm:
                            in_fm = True
                            continue
                        break
                    if not in_fm:
                        continue
                    if line.startswith("session_id:"):
                        sid = line.split(":", 1)[1].strip()
                    elif line.startswith("previous_handoff:"):
                        prev_handoff_rel = line.split(":", 1)[1].strip()
        except OSError:
            break

        if sid and sid != "unknown" and sid not in seen:
            sids.append(sid)
            seen.add(sid)

        if not prev_handoff_rel:
            break
        # Resolve the pointer relative to the handoff file's own directory
        # (flat layout: a sibling filename); fall back to the directory's
        # parent for layouts whose pointers keep a subdir prefix
        # (e.g. journal/<file>).
        candidate = cursor.parent / prev_handoff_rel
        if not candidate.is_file():
            candidate = cursor.parent.parent / prev_handoff_rel
        cursor = candidate
        depth += 1

    return sids


def build_multi_session_output(
    session_ids: list[str], base_path: Path
) -> dict[str, Any]:
    """Parse each session-id and aggregate."""
    if not session_ids:
        return {
            "status": "error",
            "summary": "No session-ids supplied for multi-session parse",
            "sessions": [],
            "aggregate": {},
        }

    sessions_out: list[dict[str, Any]] = []
    agg_tools: Counter[str] = Counter()
    agg_subagents: list[dict[str, Any]] = []
    agg_models: set[str] = set()
    agg_branches: set[str] = set()
    total_assistant = 0
    total_human = 0
    total_input = 0
    total_output = 0
    total_compactions = 0
    total_rejections = 0
    transcripts_present = 0

    for idx, sid in enumerate(session_ids):
        result = parse_one_session(sid, base_path)
        result["role"] = "current" if idx == 0 else "previous"
        sessions_out.append(result)

        if result.get("transcript_present"):
            transcripts_present += 1
            data = result["data"]
            agg_tools.update(data["tools"]["usage"])
            subagents = data["subagents"]
            agg_models.update(data["session"]["models"])
            agg_branches.update(data["session"]["git_branches"])
            total_assistant += data["turns"]["assistant"]
            total_human += data["turns"]["human_messages"]
            total_input += data["tokens"]["total_input"]
            total_output += data["tokens"]["total_output"]
            total_compactions += data["compactions"]["count"]
            total_rejections += data["tools"]["rejection_count"]
        else:
            subagents = result.get("subagents", [])

        for sub in subagents:
            tagged = dict(sub)
            tagged["session_id"] = sid
            agg_subagents.append(tagged)

    if transcripts_present == len(session_ids):
        status = "pass"
    elif transcripts_present > 0 or agg_subagents:
        # Genuine partial chain: some transcripts, or subagent evidence only.
        status = "warning"
    else:
        # Nothing found at all — a bad base dir, stale chain, or wrong SIDs
        # must fail loudly, not read as a successful all-zero retro.
        status = "error"
    summary = (
        f"Multi-session retro: {len(session_ids)} chained session(s) "
        f"({transcripts_present} with transcript), "
        f"{total_assistant} assistant turns total, "
        f"{total_human} human messages, "
        f"{total_compactions} compaction(s)"
    )

    return {
        "status": status,
        "summary": summary,
        "sessions": sessions_out,
        "aggregate": {
            "total_assistant_turns": total_assistant,
            "total_human_messages": total_human,
            "total_input_tokens": total_input,
            "total_output_tokens": total_output,
            "total_compactions": total_compactions,
            "total_tool_rejections": total_rejections,
            "all_tools": dict(agg_tools.most_common()),
            "all_subagents": agg_subagents,
            "all_models": sorted(agg_models),
            "all_branches": sorted(agg_branches),
        },
    }


def _parse_legacy_or_argparse(argv: list[str]) -> argparse.Namespace:
    """Support BOTH legacy positional 2-arg form AND new argparse-flag form.

    Legacy:  parse_transcript.py <session_id> <base_path>
    New:     parse_transcript.py --sessions SID1 SID2 ... --base <base_path>
    New:     parse_transcript.py --chain-from <handoff-file> --base <base_path>
    """
    # Detect legacy form: exactly 2 positional args, neither starts with --
    if len(argv) == 2 and not argv[0].startswith("--") and not argv[1].startswith("--"):
        return argparse.Namespace(
            session_id=argv[0],
            base=Path(argv[1]),
            sessions=None,
            chain_from=None,
        )

    parser = argparse.ArgumentParser(
        prog="parse_transcript.py",
        description="Parse Claude Code JSONL transcript(s) and emit metrics JSON.",
    )
    parser.add_argument(
        "--base", type=Path, help="Base directory containing session JSONL files"
    )
    parser.add_argument(
        "--sessions",
        nargs="+",
        help="Multiple UUIDs to parse + aggregate (first = current, rest = chained prior)",
    )
    parser.add_argument(
        "--chain-from",
        type=Path,
        dest="chain_from",
        help="Walk session chain via handoff frontmatter starting from the given log file",
    )
    parser.add_argument(
        "--current-session",
        dest="current_session",
        help="Optional current session-id to prepend when using --chain-from",
    )
    ns = parser.parse_args(argv)
    ns.session_id = None
    return ns


def main() -> None:
    argv = sys.argv[1:]
    if not argv:
        # Emit usage error before argparse can produce its own; --help/-h fall through.
        _emit_and_exit(
            "error",
            "Usage: parse_transcript.py <session_id> <base_path>  |  "
            "parse_transcript.py --sessions <sid...> --base <path>  |  "
            "parse_transcript.py --chain-from <file> --base <path>",
            {},
            2,
        )

    ns = _parse_legacy_or_argparse(argv)

    if not ns.base or not ns.base.is_dir():
        _emit_and_exit(
            "error",
            f"--base must point to an existing directory (got: {ns.base})",
            {},
            2,
        )

    # Multi-session: --chain-from
    if ns.chain_from is not None:
        if not ns.chain_from.is_file():
            _emit_and_exit(
                "error",
                f"--chain-from file not found: {ns.chain_from}",
                {},
                2,
            )
        chain_sids = extract_chain_from_handoff(ns.chain_from, ns.base)
        # Prepend current session-id if supplied AND not already first
        all_sids: list[str] = []
        if ns.current_session and ns.current_session not in chain_sids:
            all_sids.append(ns.current_session)
        all_sids.extend(chain_sids)
        output = build_multi_session_output(all_sids, ns.base)
        print(json.dumps(output, indent=2))
        sys.exit(0 if output["status"] in {"pass", "warning"} else 2)

    # Multi-session: --sessions
    if ns.sessions:
        output = build_multi_session_output(list(ns.sessions), ns.base)
        print(json.dumps(output, indent=2))
        sys.exit(0 if output["status"] in {"pass", "warning"} else 2)

    # Single-session: legacy positional path
    session_id = ns.session_id
    if not session_id:
        _emit_and_exit(
            "error",
            "No session-id supplied (positional or --sessions / --chain-from)",
            {},
            2,
        )

    result = parse_one_session(session_id, ns.base)

    if not result.get("transcript_present"):
        # Existing single-session warning vs error semantics preserved.
        if result.get("subagents"):
            _emit_and_exit(
                "warning",
                (
                    f"No main transcript found, "
                    f"but {len(result['subagents'])} subagent(s) discovered"
                ),
                {"subagents": result["subagents"]},
                1,
            )
        _emit_and_exit("error", result["error"], {}, 2)

    data = result["data"]
    output = {
        "status": "pass",
        "summary": (
            f"Session: {data['turns']['assistant']} assistant turns, "
            f"{data['turns']['human_messages']} human messages, "
            f"{data['compactions']['count']} compaction(s), "
            f"{data['session']['duration_minutes']}min"
        ),
        "data": data,
    }
    print(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()
