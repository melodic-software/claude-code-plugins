#!/usr/bin/env python3
"""Parse Claude Code JSONL transcript(s) and extract quantitative metrics.

Zero external dependencies — stdlib only.

Usage (single-session, backward compatible):
    python parse_transcript.py <session_id> <base_path>

Usage (multi-session, new):
    python parse_transcript.py --sessions <sid1> <sid2> ... --base <base_path>
    python parse_transcript.py --chain-from <handoff-file> --base <base_path>

Usage (sealed CI lane legs):
    python parse_transcript.py --legs <leg.json.gz> [<leg.json.gz> ...]

    Each file is a gzipped JSON array of stream-json messages (lane_legs.py names them). Output:
    {"status", "summary", "legs": [{"id", "path", "transcript_present", "data"}], "aggregate"}.
    Each leg's `data` is the session `data` block, its subagents tallied from the inline messages
    (`assistant_turns`, `tools`, `rejection_count`), plus `result` (the result message's subtype,
    is_error, num_turns, duration_ms, api_error_status, models, permission_denials) and
    `timing_source` (`timestamps`, `result` or `none`). Exit 0 when any leg parsed, else 2.

Arguments:
    session_id    Single UUID session identifier (positional, backward compat)
    base_path     Base directory containing session JSONL files (positional)
    --sessions    Multiple UUIDs to parse + aggregate (first = current, rest = chained prior).
                  Space-separated or comma-joined; both forms mean the same list.
    --chain-from  Walk session chain via handoff frontmatter (previous_handoff)
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
          "chain_coverage": {
            "requested": N,   # session-ids this run was asked to parse
            "found": N,       # of those, how many had a transcript
            "available": N,   # the chain: `requested`, plus under --chain-from the
                              # other transcripts that mention the handoff topic
                              # (null when <base> is unreadable under --chain-from)
            "project_transcripts": N,  # every transcript in <base>, a diagnostic
                              # never used as the denominator (null if unreadable)
            "topic": "<slug>",# the topic that scoped `available` (--chain-from only)
            "ratio": 0.0-1.0, # found / available; omitted when available is 0/null
          },
          "fork_candidates": [  # unrequested transcripts sharing record uuids with a
            {"id": "<UUID>", "shared_records": N, "shares_with": ["<UUID>", ...]},
          ],                    # requested one: forks to offer, never auto-added
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
          "handoff_journey": [  # --chain-from only: each hop, newest first, its
            {"hop": N, "session_id": "<UUID>", "date": "<ISO>", "source": "<file read>",
             "sections": {"Direction changes": [...], "This session": [...],
                          "Observations": [...]}},
          ],                    # sections read from hop files when a hot file is gone
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
import re
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Any, NoReturn, cast

_PLUGIN_SCRIPTS = str(Path(__file__).resolve().parent)
if _PLUGIN_SCRIPTS not in sys.path:
    sys.path.insert(0, _PLUGIN_SCRIPTS)

import handoff_chain  # noqa: E402  (beside this script)
import transcript_reader  # noqa: E402  (beside this script)


def parse_timestamp(ts_str: str) -> datetime | None:
    if not ts_str:
        return None
    try:
        return datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return None


# Tools whose `input.file_path` is a write target. Read/Grep/Glob also have
# file_path inputs but should not count as "files modified".
# MultiEdit stays listed on purpose: transcripts recorded by older Claude Code
# versions carry MultiEdit calls, and they must still count as modifications.
# Pointer: for where the permissions page names the legacy MultiEdit tool, see
# https://code.claude.com/docs/en/permissions#read-and-edit
# As of: 2026-10-02
# Recheck trigger: that section stops naming MultiEdit, or moves.
_FILE_MODIFYING_TOOLS = frozenset({"Write", "Edit", "MultiEdit", "NotebookEdit"})

_REJECTION_SNIPPET_LEN = 200


def _normalize_path(path: str, cwd: str | None) -> str:
    norm_path = path.replace("\\", "/").rstrip("/")
    norm_cwd = (cwd or "").replace("\\", "/").rstrip("/")
    if not norm_cwd:
        return norm_path
    if norm_path == norm_cwd:
        return "."
    return norm_path.removeprefix(norm_cwd + "/")


def _as_dict(value: Any) -> dict[str, Any]:
    return cast(dict[str, Any], value) if isinstance(value, dict) else {}


def _as_list(value: Any) -> list[Any]:
    return cast(list[Any], value) if isinstance(value, list) else []


_TYPED_COMMAND = re.compile(r"<command-name>/([^:\s<]+:[^:\s<]+)</command-name>")
_PLUGIN_SKILL = re.compile(r"[^:\s]+:[^:\s]+")


def _count_typed_plugin_skill(text: str, metrics: dict[str, Any]) -> None:
    """Count a user-typed `/<plugin>:<skill>`, which never reaches the Skill tool."""
    for match in _TYPED_COMMAND.finditer(text):
        metrics["plugin_skills"][match.group(1)] += 1


def _count_tools_and_extract_paths(content: list[Any], metrics: dict[str, Any]) -> None:
    for raw_item in content:
        if not isinstance(raw_item, dict):
            continue
        item = cast(dict[str, Any], raw_item)
        if item.get("type") != "tool_use":
            continue
        name = str(item.get("name", "unknown"))
        metrics["tool_usage"][name] += 1
        tool_input = _as_dict(item.get("input"))
        if name == "Skill":
            skill = tool_input.get("skill")
            if isinstance(skill, str) and _PLUGIN_SKILL.fullmatch(skill):
                metrics["plugin_skills"][skill] += 1
        if name in _FILE_MODIFYING_TOOLS:
            fp_candidate = tool_input.get("file_path")
            if isinstance(fp_candidate, str) and fp_candidate:
                metrics["files_modified"].add(fp_candidate)


def _new_inline_subagent(sub_id: str, spawn: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": sub_id,
        "type": str(spawn.get("subagent_type") or "unknown"),
        "description": str(spawn.get("description") or ""),
        "assistant_turns": 0,
        "tools": Counter(),
        "rejection_count": 0,
    }


def _count_inline_subagent(event: dict[str, Any], subs: dict[str, dict[str, Any]], spawns: dict[str, dict[str, Any]]) -> None:
    sub_id = str(event.get("parent_tool_use_id"))
    sub = subs.setdefault(sub_id, _new_inline_subagent(sub_id, spawns.get(sub_id, {})))
    content = _as_list(_as_dict(event.get("message")).get("content"))
    if event.get("type") == "assistant":
        sub["assistant_turns"] += 1
        for item in content:
            if isinstance(item, dict) and item.get("type") == "tool_use":
                sub["tools"][str(item.get("name", "unknown"))] += 1
    elif event.get("type") == "user":
        sub["rejection_count"] += sum(1 for item in content if isinstance(item, dict) and item.get("type") == "tool_result" and item.get("is_error"))


def _leg_result(event: dict[str, Any]) -> dict[str, Any]:
    status = event.get("api_error_status")
    denials = event.get("permission_denials")
    return {
        "subtype": event.get("subtype"),
        "is_error": event.get("is_error"),
        "num_turns": event.get("num_turns"),
        "duration_ms": event.get("duration_ms"),
        "api_error_status": status if isinstance(status, int) and not isinstance(status, bool) else None,
        "models": sorted(_as_dict(event.get("modelUsage"))),
        "permission_denials": len(denials) if isinstance(denials, list) else 0,
    }


def parse_main_transcript(filepath: Path, lane_leg: bool = False) -> dict[str, Any] | None:
    """Collect metrics from a main transcript read through the shared transcript reader.

    Tokens count once per assistant message; `human_messages` counts typed turns only. With
    `lane_leg`, the file is a sealed lane leg: its subagents' messages arrive inline, marked
    `isSidechain`, so they are tallied apart from the main thread, and its last result message is
    kept."""
    if not filepath.is_file():
        return None

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
        "queued_messages": 0,
        "plugin_skills": Counter(),
    }
    stats: dict[str, int] = {}
    # Streaming writes one message as several records; the ledger counts its usage once.
    ledger = transcript_reader.UsageLedger()
    inline_subagents: dict[str, dict[str, Any]] = {}
    agent_spawns: dict[str, dict[str, Any]] = {}
    leg_result: dict[str, Any] | None = None

    for event in transcript_reader.iter_records(filepath, stats):
        if lane_leg:
            if event.get("isSidechain"):
                _count_inline_subagent(event, inline_subagents, agent_spawns)
                continue
            if event.get("type") == "result":
                leg_result = _leg_result(event)
            for item in _as_list(_as_dict(event.get("message")).get("content")):
                if isinstance(item, dict) and item.get("type") == "tool_use" and item.get("name") in {"Agent", "Task"}:
                    agent_spawns[str(item.get("id"))] = _as_dict(item.get("input"))
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

                ledger.add(event)
                _count_tools_and_extract_paths(
                    _as_list(msg.get("content")), metrics
                )

            case "user":
                metrics["user_turns"] += 1
                if transcript_reader.is_typed_turn(event):
                    metrics["human_messages"] += 1
                # A typed /<plugin>:<skill> arrives as an injected command record, not a typed
                # turn, so the plugin-usage scan runs over every user record.
                content_raw = _as_dict(event.get("message")).get("content", [])

                if isinstance(content_raw, str):
                    _count_typed_plugin_skill(content_raw, metrics)
                    continue

                for raw_item in _as_list(content_raw):
                    if isinstance(raw_item, str):
                        _count_typed_plugin_skill(raw_item, metrics)
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
                            _count_typed_plugin_skill(
                                str(item.get("text", "")), metrics
                            )

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

            case "queue-operation":
                if event.get("operation") == "enqueue":
                    metrics["queued_messages"] += 1

            case "file-history-snapshot":
                backups = _as_dict(
                    _as_dict(event.get("snapshot")).get("trackedFileBackups")
                )
                for fpath_key in backups:
                    metrics["files_modified"].add(str(fpath_key))

    metrics["errors"].extend(
        {"type": "parse_error", "detail": "Malformed JSON line"}
        for _ in range(stats["bad_lines"] + stats["incomplete"])
    )
    tokens = ledger.totals()
    metrics["total_input_tokens"] = tokens["input"]
    metrics["total_output_tokens"] = tokens["output"]
    metrics["cache_creation_tokens"] = tokens["cache_creation"]
    metrics["cache_read_tokens"] = tokens["cache_read"]

    metrics["files_modified"] = {
        _normalize_path(p, metrics["cwd"]) for p in metrics["files_modified"]
    }

    metrics["turn_durations_ms"] = _compute_turn_deltas_ms(
        metrics["assistant_timestamps"]
    )
    if lane_leg:
        metrics["decoded_records"] = stats["records"]
        metrics["leg_result"] = leg_result
        metrics["inline_subagents"] = [
            {**sub, "tools": dict(sub["tools"].most_common())}
            for sub in inline_subagents.values()
        ]

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
    start = parse_timestamp(first_ts or "")
    end = parse_timestamp(last_ts or "")

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


def _emit_multi_and_exit(
    session_ids: list[str],
    base_path: Path,
    topic: str | None = None,
    journey: list[dict[str, Any]] | None = None,
) -> NoReturn:
    output = build_multi_session_output(session_ids, base_path, topic)
    if journey is not None:
        output["handoff_journey"] = journey
    print(json.dumps(output, indent=2))
    sys.exit(0 if output["status"] in {"pass", "warning"} else 2)


def build_session_data(
    session_id: str, metrics: dict[str, Any], subagents: list[dict[str, Any]]
) -> dict[str, Any]:
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
        "plugin_usage": {
            "skills": dict(metrics["plugin_skills"].most_common()),
        },
        "files_modified": sorted(metrics["files_modified"]),
        "subagents": subagents,
        "errors": metrics["errors"],
    }


def parse_one_session(session_id: str, base_path: Path) -> dict[str, Any]:
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

    return {
        "id": session_id,
        "transcript_present": True,
        "subagents_present": bool(subagents),
        "data": build_session_data(session_id, metrics, subagents),
    }


def extract_chain_from_handoff(
    handoff_file: Path, base_path: Path, limit: int = 1000
) -> list[str]:
    walk = handoff_chain.journey(handoff_file, limit=limit)
    if walk.stop is not None:
        print(f"warning: handoff chain {walk.stop}; stopping walk", file=sys.stderr)
    return walk.session_ids


def handoff_journey(handoff_file: Path) -> list[dict[str, Any]]:
    return [
        {
            "hop": hop.hop,
            "session_id": hop.session_id,
            "date": hop.date,
            "source": hop.source.as_posix(),
            "sections": hop.sections,
        }
        for hop in handoff_chain.journey(handoff_file).hops
    ]


UUID_RE = re.compile(r'"uuid"\s*:\s*"([^"]+)"')
HANDOFF_TOPIC_RE = re.compile(r"-handoff-(.+)\.md$")

_AGGREGATE_TOTALS = {
    "total_assistant_turns": ("turns", "assistant"),
    "total_human_messages": ("turns", "human_messages"),
    "total_input_tokens": ("tokens", "total_input"),
    "total_output_tokens": ("tokens", "total_output"),
    "total_compactions": ("compactions", "count"),
    "total_tool_rejections": ("tools", "rejection_count"),
}


def _scan_project(
    base_path: Path, session_ids: list[str], topic: str | None
) -> tuple[int, int | None, list[dict[str, Any]]]:
    """One pass over <base>/*.jsonl: (unrequested transcripts that mention
    `topic`, every transcript in the directory or None when it is unreadable,
    fork candidates).

    A fork copies its parent's records, uuids included, into a new transcript that
    no handoff points at, so uuid overlap is the only link back to the chain."""
    try:
        paths = sorted(p for p in base_path.glob("*.jsonl") if p.is_file())
    except OSError:
        return 0, None, []
    requested = set(session_ids)
    chained: dict[str, set[str]] = {}
    others: list[Path] = []
    for path in paths:
        if path.stem in requested:
            try:
                text = path.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            chained[path.stem] = set(UUID_RE.findall(text))
        else:
            others.append(path)
    mentions = 0
    forks: list[dict[str, Any]] = []
    for path in others:
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if topic and topic in text:
            mentions += 1
        uuids = set(UUID_RE.findall(text))
        shares = {sid: n for sid, own in chained.items() if (n := len(uuids & own))}
        if shares:
            forks.append(
                {
                    "id": path.stem,
                    "shared_records": max(shares.values()),
                    "shares_with": sorted(shares),
                }
            )
    forks.sort(key=lambda f: (-f["shared_records"], f["id"]))
    return mentions, len(paths), forks


def build_multi_session_output(
    session_ids: list[str], base_path: Path, topic: str | None = None
) -> dict[str, Any]:
    if not session_ids:
        return {
            "status": "error",
            "summary": "No session-ids supplied for multi-session parse",
            "sessions": [],
            "aggregate": {},
        }

    session_ids = list(dict.fromkeys(session_ids))

    sessions_out: list[dict[str, Any]] = []
    agg_tools: Counter[str] = Counter()
    agg_plugin_skills: Counter[str] = Counter()
    agg_subagents: list[dict[str, Any]] = []
    agg_models: set[str] = set()
    agg_branches: set[str] = set()
    totals = dict.fromkeys(_AGGREGATE_TOTALS, 0)
    transcripts_present = 0

    for idx, sid in enumerate(session_ids):
        result = parse_one_session(sid, base_path)
        result["role"] = "current" if idx == 0 else "previous"
        sessions_out.append(result)

        if result.get("transcript_present"):
            transcripts_present += 1
            data = result["data"]
            agg_tools.update(data["tools"]["usage"])
            agg_plugin_skills.update(data["plugin_usage"]["skills"])
            subagents = data["subagents"]
            agg_models.update(data["session"]["models"])
            agg_branches.update(data["session"]["git_branches"])
            for key, (section, field) in _AGGREGATE_TOTALS.items():
                totals[key] += data[section][field]
        else:
            subagents = result.get("subagents", [])

        agg_subagents.extend({**sub, "session_id": sid} for sub in subagents)

    # The denominator is the chain: the sessions requested (the walk, under
    # --chain-from), plus under --chain-from the other transcripts that mention
    # the handoff topic, which are the sessions a walk that stopped early did
    # not reach. Every transcript in the project directory is NOT the chain: a
    # $HOME-launched project slug holds every session ever run on the machine,
    # so that count is reported apart as `project_transcripts`. An unreadable
    # base directory leaves the topic count unknown, so `available` is null then.
    mentions, project_transcripts, fork_candidates = _scan_project(
        base_path, session_ids, topic
    )
    available: int | None = len(session_ids) + mentions
    if topic and project_transcripts is None:
        available = None
    chain_coverage: dict[str, Any] = {
        "requested": len(session_ids),
        "found": transcripts_present,
        "available": available,
        "project_transcripts": project_transcripts,
    }
    if topic:
        chain_coverage["topic"] = topic
    coverage_note = ""
    if available:
        chain_coverage["ratio"] = round(transcripts_present / available, 3)
        scope = f"in the chain or mentioning '{topic}'" if topic else "in the chain"
        coverage_note = (
            f", covering {transcripts_present} of {available} transcript(s) {scope}"
        )
    if fork_candidates:
        coverage_note += (
            f"; {len(fork_candidates)} unchained fork candidate(s) share records "
            "with the chain"
        )

    if transcripts_present == len(session_ids):
        status = "pass"
    elif transcripts_present > 0 or agg_subagents:
        status = "warning"
    else:
        status = "error"
    summary = (
        f"Multi-session retro: {len(session_ids)} chained session(s) "
        f"({transcripts_present} with transcript), "
        f"{totals['total_assistant_turns']} assistant turns total, "
        f"{totals['total_human_messages']} human messages, "
        f"{totals['total_compactions']} compaction(s)"
        f"{coverage_note}"
    )

    return {
        "status": status,
        "summary": summary,
        "chain_coverage": chain_coverage,
        "fork_candidates": fork_candidates,
        "sessions": sessions_out,
        "aggregate": {
            **totals,
            "all_tools": dict(agg_tools.most_common()),
            "all_plugin_skills": dict(agg_plugin_skills.most_common()),
            "all_subagents": agg_subagents,
            "all_models": sorted(agg_models),
            "all_branches": sorted(agg_branches),
        },
    }


def parse_one_leg(path: Path) -> dict[str, Any]:
    leg_id = path.name.removesuffix(".gz").removesuffix(".json")
    metrics = parse_main_transcript(path, lane_leg=True)
    if metrics is None:
        return {"id": leg_id, "path": str(path), "transcript_present": False, "error": f"No leg transcript at {path}"}
    if metrics["decoded_records"] == 0:
        return {"id": leg_id, "path": str(path), "transcript_present": False, "error": f"unreadable leg transcript at {path}: no message decoded"}
    data = build_session_data(leg_id, metrics, metrics["inline_subagents"])
    result = metrics["leg_result"]
    data["result"] = result
    data["timing_source"] = "timestamps" if metrics["first_timestamp"] else "none"
    if not metrics["first_timestamp"] and result and isinstance(result.get("duration_ms"), int):
        data["timing_source"] = "result"
        data["session"]["duration_minutes"] = round(result["duration_ms"] / 60000, 1)
    return {"id": leg_id, "path": str(path), "transcript_present": True, "data": data}


def build_legs_output(paths: list[Path]) -> dict[str, Any]:
    legs = [parse_one_leg(p) for p in dict.fromkeys(paths)]
    present = [leg for leg in legs if leg["transcript_present"]]
    totals = dict.fromkeys(_AGGREGATE_TOTALS, 0)
    tools: Counter[str] = Counter()
    models: set[str] = set()
    for leg in present:
        data = leg["data"]
        tools.update(data["tools"]["usage"])
        models.update(data["session"]["models"])
        models.update((data["result"] or {}).get("models", []))
        for key, (section, field) in _AGGREGATE_TOTALS.items():
            totals[key] += data[section][field]
    status = "pass" if len(present) == len(legs) else "warning" if present else "error"
    return {
        "status": status,
        "summary": (
            f"Lane legs: {len(legs)} requested ({len(present)} found), "
            f"{totals['total_assistant_turns']} assistant turns, "
            f"{totals['total_tool_rejections']} tool rejection(s), "
            f"{totals['total_compactions']} compaction(s)"
        ),
        "legs": legs,
        "aggregate": {**totals, "all_tools": dict(tools.most_common()), "all_models": sorted(models)},
    }


def _parse_legacy_or_argparse(argv: list[str]) -> argparse.Namespace:
    if len(argv) == 2 and not argv[0].startswith("--") and not argv[1].startswith("--"):
        return argparse.Namespace(
            session_id=argv[0],
            base=Path(argv[1]),
            sessions=None,
            chain_from=None,
            legs=None,
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
        "--legs",
        nargs="+",
        type=Path,
        help="Sealed lane leg transcripts (gzipped stream-json arrays) to parse + aggregate",
    )
    parser.add_argument(
        "--current-session",
        dest="current_session",
        help="Optional current session-id to prepend when using --chain-from",
    )
    ns = parser.parse_args(argv)
    ns.session_id = None
    if ns.sessions:
        # `nargs="+"` takes `--sessions a,b,c` as one token. A session id never
        # contains a comma, so split on it and drop empty fragments.
        ns.sessions = [
            sid
            for token in ns.sessions
            for sid in (part.strip() for part in token.split(","))
            if sid
        ]
    return ns


def main() -> None:
    argv = sys.argv[1:]
    if not argv:
        _emit_and_exit(
            "error",
            "Usage: parse_transcript.py <session_id> <base_path>  |  "
            "parse_transcript.py --sessions <sid...> --base <path>  |  "
            "parse_transcript.py --chain-from <file> --base <path>",
            {},
            2,
        )

    ns = _parse_legacy_or_argparse(argv)

    if ns.legs:
        output = build_legs_output(ns.legs)
        print(json.dumps(output, indent=2))
        sys.exit(0 if output["status"] in {"pass", "warning"} else 2)

    if not ns.base or not ns.base.is_dir():
        _emit_and_exit(
            "error",
            f"--base must point to an existing directory (got: {ns.base})",
            {},
            2,
        )

    if ns.chain_from is not None:
        if not ns.chain_from.is_file():
            _emit_and_exit(
                "error",
                f"--chain-from file not found: {ns.chain_from}",
                {},
                2,
            )
        chain_sids = extract_chain_from_handoff(ns.chain_from, ns.base)
        all_sids: list[str] = []
        if ns.current_session and ns.current_session not in chain_sids:
            all_sids.append(ns.current_session)
        all_sids.extend(chain_sids)
        m = HANDOFF_TOPIC_RE.search(ns.chain_from.name)
        _emit_multi_and_exit(
            all_sids,
            ns.base,
            m.group(1) if m else None,
            handoff_journey(ns.chain_from),
        )

    if ns.sessions:
        _emit_multi_and_exit(ns.sessions, ns.base)

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
        # Warning vs error here is contract: see the module docstring's exit codes.
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
