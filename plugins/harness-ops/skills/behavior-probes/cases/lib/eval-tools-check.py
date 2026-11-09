#!/usr/bin/env python3
"""Run one `claude plugin eval` case and report the tools its session had.

The scaffold writes a fixture plugin beside this file whose one eval case lists
only Read, Glob and Grep in allowed_tools and asks for one call each to Skill,
Task, TaskStop and ToolSearch. This runs that case once, with no --allow-tools
grant and TMPDIR set to a short directory under HOME (removed afterwards),
keeps the run's trace, and prints one line:

  eval-tools: Skill=<state> Task=<state> TaskStop=<state> ToolSearch=<state>
  claude=<version> offered=<the init line's tools, comma-joined>

on a single line, each <state> one of:

  absent      not in the init tools and never called
  not-called  in the init tools, never called
  denied      called, and the trace records a permission denial for the call
  refused     called, error result with no denial
  ran         called, result with no error
  no-result   called, no result in the trace

The states come first so a clipped line still holds them. Exits 1 with no such
line when the eval does not run or its kept trace cannot be read. Standard
library only.
"""

from __future__ import annotations

import contextlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

WATCHED = ("Skill", "Task", "TaskStop", "ToolSearch")
# The init line names the Agent tool Task; a call may carry either name.
ALIASES = {"Agent": "Task"}
# An is_error tool result carrying this text is a denial too.
DENIAL_TEXT = "denied by your permission settings"
EVAL_TIMEOUT = 540
MAX_TMPDIR = 24


def fail(message: str) -> int:
    print(f"eval-tools-check: {message}", file=sys.stderr)
    return 1


def read_lines(path: Path) -> list[dict]:
    lines = []
    for text in path.read_text(encoding="utf-8").splitlines():
        try:
            line = json.loads(text)
        except ValueError:
            continue
        if isinstance(line, dict):
            lines.append(line)
    return lines


def text_of(content) -> str:
    if isinstance(content, list):
        return " ".join(str(p.get("text", "")) for p in content if isinstance(p, dict))
    return "" if content is None else str(content)


def states(trace: list[dict]) -> tuple[str, list[str], dict[str, str]]:
    version, offered = "unknown", []
    calls: dict[str, str] = {}
    results: dict[str, tuple[bool, str]] = {}
    denied: set[str] = set()
    for line in trace:
        kind = (line.get("type"), line.get("subtype"))
        if kind == ("system", "init") and not offered:
            version = str(line.get("claude_code_version") or "unknown")
            offered = [str(t) for t in line.get("tools") or []]
        elif kind == ("system", "permission_denied") and line.get("tool_use_id"):
            denied.add(line["tool_use_id"])
        elif line.get("type") == "result":
            for entry in line.get("permission_denials") or []:
                if isinstance(entry, dict) and entry.get("tool_use_id"):
                    denied.add(entry["tool_use_id"])
        content = (line.get("message") or {}).get("content")
        for block in content if isinstance(content, list) else []:
            if not isinstance(block, dict):
                continue
            if block.get("type") == "tool_use":
                name = ALIASES.get(block.get("name"), block.get("name"))
                if name in WATCHED and name not in calls:
                    calls[name] = block.get("id")
            elif block.get("type") == "tool_result":
                results[block.get("tool_use_id")] = (
                    bool(block.get("is_error")),
                    text_of(block.get("content")),
                )
    offered_names = {ALIASES.get(t, t) for t in offered}
    found = {}
    for name in WATCHED:
        use_id = calls.get(name)
        if use_id is None:
            found[name] = "not-called" if name in offered_names else "absent"
        elif use_id in denied:
            found[name] = "denied"
        elif use_id not in results:
            found[name] = "no-result"
        else:
            is_error, text = results[use_id]
            if not is_error:
                found[name] = "ran"
            else:
                found[name] = "denied" if DENIAL_TEXT in text.lower() else "refused"
    return version, offered, found


def eval_tmpdir() -> Path | None:
    """A short temp directory under HOME for the nested run, or None when none fits.

    The run's shell sandbox names Unix sockets inside its temp directory, and a
    long or system temp path can leave the session with no shell (the evals
    plugin's sandboxes reference, "Sandbox start")."""
    home = os.environ.get("HOME")
    if not home:
        return None
    path = Path(tempfile.mkdtemp(prefix="pe", dir=home))
    if len(str(path)) > MAX_TMPDIR:
        shutil.rmtree(path, ignore_errors=True)
        return None
    return path


def remove_tree(path: Path) -> None:
    """Remove path, first giving the owner rwx on every directory in it.

    A kept eval temp tree holds directories sealed at mode 000, which a plain
    rmtree cannot enter."""
    for top, dirs, _ in os.walk(path):
        for name in dirs:
            child = os.path.join(top, name)
            if os.path.islink(child):
                continue  # never change a link's target outside the tree
            with contextlib.suppress(OSError):
                os.chmod(child, 0o700)
    shutil.rmtree(path, ignore_errors=True)


def main() -> int:
    here = Path(__file__).resolve().parent
    plugin = here / "eval-tools-plugin"
    out = here / "eval-tools-result.json"
    tmp = eval_tmpdir()
    if tmp is None:
        return fail(f"no temp directory of at most {MAX_TMPDIR} characters under HOME")
    try:
        return report(plugin, out, tmp)
    finally:
        remove_tree(tmp)


def report(plugin: Path, out: Path, tmp: Path) -> int:
    argv = [
        "claude", "plugin", "eval", str(plugin),
        "--runs", "1", "--ablation", "none", "--trust-plugin", "--keep-temp",
        "--no-publish", "--max-cost-usd", "1", "--json", str(out),
    ]
    try:
        subprocess.run(  # noqa: S603 - argv list, no shell
            argv,
            env={**os.environ, "TMPDIR": str(tmp)},
            capture_output=True,
            text=True,
            timeout=EVAL_TIMEOUT,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return fail(f"claude plugin eval did not finish: {exc}")
    try:
        result = json.loads(out.read_text(encoding="utf-8"))
        run = result["cases"][0]["arms"]["with"][0]
        trace_path = run["tracePath"]
    except (OSError, ValueError, KeyError, IndexError, TypeError) as exc:
        return fail(f"no run with a tracePath in {out.name}: {exc!r}")
    if not os.path.isabs(trace_path):
        trace_path = str(out.parent / trace_path)
    try:
        trace = read_lines(Path(trace_path))
    except OSError as exc:
        return fail(f"kept trace unreadable: {exc}")
    version, offered, found = states(trace)
    if not offered:
        return fail("the trace has no init line with a tools list")
    marks = " ".join(f"{name}={found[name]}" for name in WATCHED)
    print(f"eval-tools: {marks} claude={version} offered={','.join(offered)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
