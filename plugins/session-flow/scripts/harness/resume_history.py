#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from hop_chain import between_rails  # noqa: E402

WHOLE_MAX = 60_000
PAGED_MAX = 100_000
PAGE_LINES = 150
TOP_LINES = 100
TAIL_LINES = 80


def _numbered(lines: list[str], start: int) -> str:
    """Lines in the Read tool's `cat -n` form, numbered from `start` (1-based)."""
    return "\n".join(f"{start + i:>6}\t{line}" for i, line in enumerate(lines))


def _read(
    path: Path, lines: list[str], offset: int | None = None, limit: int | None = None
) -> dict:
    start = offset or 1
    end = len(lines) if limit is None else min(len(lines), start - 1 + limit)
    tool_input: dict = {"file_path": str(path)}
    if offset is not None:
        tool_input["offset"] = offset
    if limit is not None:
        tool_input["limit"] = limit
    return {
        "role": "tool",
        "name": "Read",
        "input": tool_input,
        "result": _numbered(lines[start - 1 : end], start),
    }


def _grep(
    path: Path,
    lines: list[str],
    fixed: list[str] | None,
    heading: bool,
    description: str,
) -> dict:
    if heading:
        command = f"grep -n '^## ' {path}"
        hits = [(i, line) for i, line in enumerate(lines, 1) if line.startswith("## ")]
    else:
        command = (
            "grep -nF " + " ".join(f"-e '{tag}'" for tag in fixed or []) + f" {path}"
        )
        hits = [
            (i, line)
            for i, line in enumerate(lines, 1)
            if any(t in line for t in fixed or [])
        ]
    return {
        "role": "tool",
        "name": "Bash",
        "input": {"command": command, "description": description},
        "result": "\n".join(f"{i}:{line}" for i, line in hits),
    }


def _section_span(
    lines: list[str], title: str, until: str | None = None
) -> tuple[int, int]:
    start = lines.index(f"## {title}") + 1
    ends = (
        i
        for i in range(start, len(lines))
        if (lines[i] == f"## {until}" if until else lines[i].startswith("## "))
    )
    return start, next(ends, len(lines)) - start + 1


def read_turns(path: Path, pattern: str | None = None) -> list[dict]:
    """The reads a real resume makes of one handoff (AUDIT.md Q2): a small file in one
    Read, a mid-size one in pages, a large one partially (a heading grep, the top 100
    lines, the hot block from Remaining actions to Prior sessions, the tail, and a
    grep for the two newest hop tags); `partial+constraints` adds a full read of
    Constraints, as the audited superseded-rule resume made."""
    text = path.read_text(encoding="utf-8")
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines = lines[:-1]
    size = len(text.encode("utf-8"))
    pattern = pattern or (
        "whole" if size <= WHOLE_MAX else "paged" if size <= PAGED_MAX else "partial"
    )
    if pattern == "whole":
        return [_read(path, lines)]
    if pattern == "paged":
        return [
            _read(path, lines, offset=start, limit=PAGE_LINES)
            for start in range(1, len(lines) + 1, PAGE_LINES)
        ]
    if pattern not in ("partial", "partial+constraints"):
        raise ValueError(f"unknown read pattern {pattern!r}")
    hops = [int(h) for h in re.findall(r"\[h(\d+)\]", text)]
    newest = max(hops) if hops else 1
    tags = [f"[h{newest - 1}]", f"[h{newest}]"] if newest > 1 else [f"[h{newest}]"]
    turns = [
        _grep(path, lines, None, True, "List the handoff's section headings"),
        _read(path, lines, limit=TOP_LINES),
    ]
    if pattern == "partial+constraints":
        start, count = _section_span(lines, "Constraints that must hold")
        turns.append(_read(path, lines, offset=start, limit=count))
    start, count = _section_span(
        lines, "Remaining actions, in order", until="Prior sessions"
    )
    turns.append(_read(path, lines, offset=start, limit=count))
    turns.append(_read(path, lines, offset=max(1, len(lines) - TAIL_LINES + 1)))
    turns.append(_grep(path, lines, tags, False, "Find the newest hop entries"))
    return turns


def _expand(value, subs: dict):
    if isinstance(value, str):
        for key, sub in subs.items():
            value = value.replace("{" + key + "}", sub)
        return value
    if isinstance(value, list):
        return [_expand(v, subs) for v in value]
    if isinstance(value, dict):
        return {k: _expand(v, subs) for k, v in value.items()}
    return value


def seed_history(
    case_spec: dict, chain: list[Path], repo_root: Path | None = None
) -> list[dict]:
    """The session every arm's writer resumes from, as `resume_eval.render_history`
    turns. It opens with the newest handoff's pasted resume prompt, then the reads,
    then the case's work turns, and ends on an assistant turn; the harness sends
    `writer.interrupt` next. `{repo}` and `{handoff}` in work turns expand to the
    repository and the newest handoff's paths.

    Raises ValueError when an injection's `visible_in_reads` disagrees with the read
    slices, or when a turn the reads did not produce restates a hidden injection."""
    newest = Path(chain[-1])
    repo = Path(repo_root) if repo_root else newest.parents[2]
    seed = case_spec["seed"]
    paste = between_rails(newest.read_text(encoding="utf-8"))
    if paste is None:
        raise ValueError(f"{newest.name}: no resume region between rails")
    reads = read_turns(newest, (seed.get("reads") or {}).get("pattern"))
    subs = {"repo": str(repo), "handoff": str(newest)}
    history = seed.get("history") or {}
    work = _expand(list(history.get("work", [])), subs)
    turns = [{"role": "user", "text": paste}, *reads]
    turns.append({"role": "assistant", "text": _expand(history["after_reads"], subs)})
    turns += work
    if turns[-1]["role"] != "assistant":
        raise ValueError(f"{case_spec['name']}: history must end on an assistant turn")

    seen = "\n".join(turn["result"] for turn in reads)
    said = "\n".join(
        turn.get("text") or json.dumps(turn.get("input")) + str(turn.get("result"))
        for turn in turns
        if turn not in reads
    )
    for item in seed["predecessor"].get("injections", []):
        visible = item.get("visible_in_reads")
        if visible is None:
            continue
        lines = item["text"].split("\n")
        shown = all(line in seen for line in lines)
        if shown != bool(visible):
            raise ValueError(
                f"{case_spec['name']}: injection {item['id']!r} visible_in_reads={visible} "
                f"but the read slices {'show' if shown else 'miss'} it"
            )
        if not visible and any(line in said for line in lines):
            raise ValueError(
                f"{case_spec['name']}: a work turn restates hidden injection {item['id']!r}"
            )
    return turns
