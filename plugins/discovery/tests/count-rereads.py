#!/usr/bin/env python3
"""Count redundant file reads in one subagent transcript.

Usage: python3 count-rereads.py <agent-transcript.jsonl>

A turn is one distinct assistant message.id, the unit turns-to-complete.py
counts. Reads are `Read` tool calls and Bash `cat`, `sed -n` or `head` on one
file; a `Read` with an offset or limit is a partial read and is ignored.

  REREAD: <path>       a full read of a file already read with no Edit or
                       Write to it in between
  SCAN->READ: <path>   a Grep or Bash grep/ls that targets the file (for ls,
                       its directory) and a full read of it on a later turn

Prints paths and counts only, never transcript content. The handback turn is
the last assistant message that has a `status:` line or a `SubagentHandback`
tool call.

Exit 0 = report printed; exit 2 = usage error or unreadable transcript.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import sys

EDIT_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}
STATUS_LINE = re.compile(r"^\s*status:", re.MULTILINE)
SHELL_OPERATORS = re.compile(r"[|;&<>`$]")


def norm(path: str, cwd: str) -> str:
    return os.path.normpath(os.path.join(cwd, os.path.expanduser(path)))


def operands(tokens: list[str], value_flags: tuple[str, ...] = ()) -> list[str]:
    out: list[str] = []
    skip = False
    for tok in tokens:
        if skip:
            skip = False
        elif tok in value_flags:
            skip = True
        elif not tok.startswith("-") or tok == "-":
            out.append(tok)
    return out


def bash_effect(command: str) -> tuple[str, str, list[str]] | None:
    """Classify a simple Bash command as (kind, program, paths), else None."""
    if SHELL_OPERATORS.search(command):
        return None
    try:
        tokens = shlex.split(command)
    except ValueError:
        return None
    if not tokens:
        return None
    prog, args = tokens[0], tokens[1:]
    if prog == "cat":
        files = operands(args)
    elif prog == "head":
        files = operands(args, ("-n", "-c"))
    elif prog == "sed" and "-n" in args:
        files = operands(args)[1:]  # the first operand is the script
    elif prog == "grep":
        files = operands(args, ("-e", "-f", "-m", "-A", "-B", "-C"))
        # the first operand is the pattern unless -e or -f supplied it
        return "scan", prog, files if "-e" in args or "-f" in args else files[1:]
    elif prog == "ls":
        return "scan", prog, operands(args)
    else:
        return None
    return ("read", prog, files) if len(files) == 1 else None


def collect(path: str) -> tuple[list[tuple[int, str, str, str]], dict[int, str], int]:
    """Return (events, text per turn, turn count); an event is (turn, kind, tool, path)."""
    turn_of: dict[str, int] = {}
    text_of: dict[int, str] = {}
    events: list[tuple[int, str, str, str]] = []
    cwd = ""
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            if not isinstance(rec, dict):
                continue
            cwd = rec.get("cwd") or cwd
            msg = rec.get("message")
            if rec.get("type") != "assistant" or not isinstance(msg, dict):
                continue
            mid = msg.get("id")
            if not mid:
                continue
            turn = turn_of.setdefault(mid, len(turn_of) + 1)
            blocks = msg.get("content")
            for block in blocks if isinstance(blocks, list) else []:
                if not isinstance(block, dict):
                    continue
                if block.get("type") == "text" and isinstance(block.get("text"), str):
                    text_of[turn] = text_of.get(turn, "") + "\n" + block["text"]
                if block.get("type") != "tool_use":
                    continue
                name, inp = block.get("name"), block.get("input")
                inp = inp if isinstance(inp, dict) else {}
                if name == "SubagentHandback":
                    text_of[turn] = text_of.get(turn, "") + "\nstatus: handback"
                target = (
                    inp.get("file_path") or inp.get("path") or inp.get("notebook_path")
                )
                has_target = isinstance(target, str)
                if name == "Read" and has_target:
                    if "offset" not in inp and "limit" not in inp:
                        events.append((turn, "read", name, norm(target, cwd)))
                elif name in EDIT_TOOLS and has_target:
                    events.append((turn, "edit", name, norm(target, cwd)))
                elif name == "Grep" and has_target:
                    events.append((turn, "scan", name, norm(target, cwd)))
                elif name == "Bash" and isinstance(inp.get("command"), str):
                    effect = bash_effect(inp["command"])
                    if effect:
                        kind, prog, files = effect
                        events.extend((turn, kind, prog, norm(f, cwd)) for f in files)
    return events, text_of, len(turn_of)


def analyze(path: str) -> dict:
    events, text_of, turns = collect(path)
    rereads: list[str] = []
    scan_reads: list[str] = []
    seen: set[str] = set()
    scanned: dict[str, tuple[int, str]] = {}  # scan target -> (earliest turn, tool)
    for turn, kind, tool, target in events:
        if kind == "edit":
            seen.discard(target)
        elif kind == "scan":
            scanned.setdefault(target, (turn, tool))
        else:
            if target in seen:
                rereads.append(target)
            seen.add(target)
            for key in (target, os.path.dirname(target)):
                hit = scanned.get(key)
                if hit and hit[0] < turn and (key == target or hit[1] == "ls"):
                    scan_reads.append(target)
                    del scanned[key]
                    break
    handback = [t for t, text in text_of.items() if STATUS_LINE.search(text)]
    return {
        "turns": turns,
        "handback": max(handback) if handback else None,
        "rereads": rereads,
        "scan_reads": scan_reads,
    }


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] in ("-h", "--help"):
        print(__doc__, file=sys.stderr)
        return 2
    try:
        result = analyze(sys.argv[1])
    except (OSError, UnicodeDecodeError) as exc:
        print(f"error: cannot read transcript: {exc}", file=sys.stderr)
        return 2
    for p in result["rereads"]:
        print(f"REREAD: {p}")
    for p in result["scan_reads"]:
        print(f"SCAN->READ: {p}")
    print(f"turns: {result['turns']}")
    print(f"handback turn: {result['handback'] or 'none'}")
    print(f"REREAD count: {len(result['rereads'])}")
    print(f"SCAN->READ count: {len(result['scan_reads'])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
