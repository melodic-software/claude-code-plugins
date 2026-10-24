#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Resume-accuracy eval harness for /session-flow:handoff (PLAN.md Phase 1).

Seeds one synthetic session state per case, has each arm carry that state across a
session boundary (a handoff, a free-hand summary, or native /compact), resumes a
fresh reader (Claude Code or Codex), and grades the reader's actions and answers
against the case's probes. Results are written in plugin eval's result schema so
`noise-report.py --baseline` compares any two arms.

Stdlib only; Python 3.10+.
"""

from __future__ import annotations

import json
import os
import re
import uuid
from dataclasses import dataclass
from pathlib import Path

MODEL_ID = "claude-opus-5-5"

# The Brief's first tool state change: edit, write, push, merge, ready, agent
# dispatch, message. A plain-text reply is not one.
STATE_CHANGE_TOOLS = frozenset(
    {"Edit", "Write", "NotebookEdit", "Agent", "Task", "SendMessage"}
)
STATE_CHANGE_COMMAND_RE = re.compile(
    r"\bgit\s+push\b|\bgh\s+pr\s+(?:merge|ready|create|comment|review|close)\b"
    r"|\bgh\s+issue\s+(?:create|comment|close)\b"
)
# Tools no eval child may use: the network, and every route to a live session or a
# scheduler on the operator's machine (probes.md P7 addendum).
DISALLOWED_TOOLS = (
    "WebFetch",
    "WebSearch",
    "SendMessage",
    "ListAgents",
    "RemoteTrigger",
    "CronCreate",
    "CronDelete",
    "PushNotification",
    "ScheduleWakeup",
)
# Inherited variables that would let a child message the parent's peer sessions or
# reach GitHub with the operator's credential.
SCRUBBED_ENV = (
    "CLAUDE_CODE_MESSAGING_SOCKET",
    "CLAUDE_CODE_MESSAGING_TOKEN",
    "CLAUDE_CODE_BRIDGE_SESSION_ID",
    "GH_TOKEN",
    "GITHUB_TOKEN",
)
TOKEN_KEYS = (
    "input_tokens",
    "cache_creation_input_tokens",
    "cache_read_input_tokens",
    "output_tokens",
)


NETWORK_DENY = (
    "Bash(curl:*)",
    "Bash(curl *)",
    "Bash(wget:*)",
    "Bash(wget *)",
    "Bash(git ls-remote:*)",
    "Bash(git ls-remote *)",
    "Bash(git fetch https:*)",
    "Bash(git fetch https *)",
    "Bash(git fetch git@*)",
    "WebFetch",
    "WebSearch",
)


def run_settings(plugin_configs: dict | None = None) -> dict:
    """`--settings` for a real-setup run: the installed session-flow off, so only the copy
    under test loads (probes.md P7), the network denied, and any option a case sets."""
    doc: dict = {
        "enabledPlugins": {"session-flow@melodic-software": False},
        "permissions": {"deny": list(NETWORK_DENY)},
    }
    if plugin_configs:
        doc["pluginConfigs"] = plugin_configs
    return doc


def claude_command(
    prompt: str,
    *,
    plugin_dir: str | None,
    settings: str,
    mcp_config: str,
    resume: str | None = None,
) -> list[str]:
    """A real-setup `claude -p` run in the lanes' permission mode (AGENTS.md)."""
    cmd = ["claude", "-p", "--model", MODEL_ID, "--permission-mode", "auto"]
    if plugin_dir:
        cmd += ["--plugin-dir", plugin_dir]
    cmd += ["--settings", settings, "--strict-mcp-config", "--mcp-config", mcp_config]
    cmd += ["--disallowed-tools", *DISALLOWED_TOOLS]
    cmd += ["--output-format", "stream-json", "--verbose"]
    if resume:
        cmd += ["--resume", resume]
    return [*cmd, prompt]


def codex_command(prompt: str, *, model: str, workdir: str, reply: str) -> list[str]:
    """A Codex reader run; the model is read once per eval and passed every time."""
    return [
        "codex",
        "exec",
        "--json",
        "--ephemeral",
        "--ignore-user-config",
        "--skip-git-repo-check",
        "-s",
        "workspace-write",
        "-m",
        model,
        "-C",
        workdir,
        "-o",
        reply,
        prompt,
    ]


GIB = 1024**3
# Floors checked before every batch (PLAN.md Approach, host resources): /tmp is a small
# tmpfs that guard hooks and other sessions need, and RAM is shared with them.
RESOURCE_FLOORS = (
    ("root_free", lambda v: v < 50 * GIB, "root disk under 50 GB free"),
    ("tmp_free", lambda v: v < 500 * 1024**2, "/tmp under 500 MB free"),
    ("tmp_inodes", lambda v: v < 50_000, "/tmp under 50,000 free inodes"),
    ("mem_available", lambda v: v < 8 * GIB, "MemAvailable under 8 GiB"),
    ("swap_used", lambda v: v > 6 * GIB, "swap in use over 6 GiB"),
)


def resource_stops(reading: dict) -> list[str]:
    """Why a batch must not start, one reason per broken floor; empty means go."""
    return [reason for key, broken, reason in RESOURCE_FLOORS if broken(reading[key])]


def resource_reading() -> dict:
    """The host figures `resource_stops` checks, read from statvfs and /proc/meminfo."""
    root, tmp = os.statvfs("/"), os.statvfs("/tmp")
    meminfo = {}
    with open("/proc/meminfo", encoding="utf-8") as handle:
        for line in handle:
            key, value = line.split(":", 1)
            meminfo[key] = int(value.split()[0]) * 1024
    return {
        "root_free": root.f_bavail * root.f_frsize,
        "tmp_free": tmp.f_bavail * tmp.f_frsize,
        "tmp_inodes": tmp.f_favail,
        "mem_available": meminfo["MemAvailable"],
        "swap_used": meminfo["SwapTotal"] - meminfo["SwapFree"],
    }


def proc_entry(pid: int) -> tuple[int, list[str]] | None:
    """(parent pid, argv) of a Linux process, or None when it cannot be read."""
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as handle:
            argv = [
                part.decode("utf-8", "replace")
                for part in handle.read().split(b"\0")
                if part
            ]
        with open(f"/proc/{pid}/stat", encoding="utf-8") as handle:
            ppid = int(handle.read().rsplit(")", 1)[1].split()[1])
    except (OSError, ValueError, IndexError):
        return None
    return ppid, argv


def isolated_session(pid: int, read=proc_entry) -> str | None:
    """The argv of an ancestor `claude` started with --worktree/-w, else None.

    The Bash guard refuses `claude plugin eval` in such a session, so the harness must
    not start there and run it as a child (that would route around the refusal). A
    session that entered a worktree with EnterWorktree mid-session does not show in
    argv and is not caught here.
    """
    seen = set()
    while pid > 1 and pid not in seen:
        seen.add(pid)
        entry = read(pid)
        if entry is None:
            return None
        pid, argv = entry
        if (
            argv
            and argv[0].rsplit("/", 1)[-1] == "claude"
            and ("--worktree" in argv or "-w" in argv)
        ):
            return " ".join(argv)
    return None


def child_env(parent: dict, *, tmpdir: str, stub_bin: str, gh_config: str) -> dict:
    """Environment for an eval child: scrubbed, stub `gh` first on PATH, an empty gh config.

    `tmpdir` must be short: a long TMPDIR stops the plugin-eval sandbox from creating
    its sockets, and every Bash call then fails (probes.md P9).
    """
    env = {key: value for key, value in parent.items() if key not in SCRUBBED_ENV}
    env["TMPDIR"] = tmpdir
    env["GH_CONFIG_DIR"] = gh_config
    env["PATH"] = f"{stub_bin}:{parent.get('PATH', '')}"
    return env


def project_key(cwd: str) -> str:
    """Directory name Claude Code keeps a cwd's transcripts under (every / and . becomes -)."""
    return cwd.replace("/", "-").replace(".", "-")


def state_change_label(block: dict) -> str | None:
    """Name a tool_use block that changes state, or None for a read."""
    name = block.get("name", "")
    if name in STATE_CHANGE_TOOLS:
        return name
    command = (block.get("input") or {}).get("command")
    if (
        name == "Bash"
        and isinstance(command, str)
        and STATE_CHANGE_COMMAND_RE.search(command)
    ):
        return f"Bash: {command}"
    return None


def reader_tokens(events: list[dict]) -> dict:
    """Token metrics of a Claude Code stream-json run up to its first state change.

    m1: input + cache creation + cache read + output summed per call (the ship-rule metric).
    m2: context at the last counted call plus summed output. m3: m1 without cache reads.
    A message id split across several events is counted once. With no state change the
    whole run counts.
    """
    seen: dict[str, dict] = {}
    state_change = None
    for event in events:
        if event.get("type") != "assistant":
            continue
        message = event.get("message") or {}
        msg_id = str(message.get("id") or f"no-id-{len(seen)}")
        if msg_id not in seen:
            seen[msg_id] = {
                key: int((message.get("usage") or {}).get(key) or 0)
                for key in TOKEN_KEYS
            }
        for block in message.get("content") or []:
            if block.get("type") == "tool_use":
                state_change = state_change_label(block)
                if state_change:
                    break
        if state_change:
            break
    calls = list(seen.values())
    last = calls[-1] if calls else dict.fromkeys(TOKEN_KEYS, 0)
    output = sum(call["output_tokens"] for call in calls)
    return {
        "calls": len(calls),
        "state_change": state_change,
        "m1": sum(sum(call.values()) for call in calls),
        "m2": last["input_tokens"]
        + last["cache_creation_input_tokens"]
        + last["cache_read_input_tokens"]
        + output,
        "m3": sum(
            call["input_tokens"]
            + call["cache_creation_input_tokens"]
            + call["output_tokens"]
            for call in calls
        ),
    }


def codex_tokens(events: list[dict]) -> dict:
    """Token metrics of a `codex exec --json` run.

    Codex reports usage per turn only (probes.md P5), so every turn up to and including
    the one holding the first state change counts whole. `input_tokens` already includes
    `cached_input_tokens`; reasoning tokens are taken as part of `output_tokens`
    (UNVERIFIED: the P5 probe run reported 0 reasoning tokens).
    m1 = input + output; m3 = m1 less cached input.
    """
    turns = m1 = m3 = 0
    state_change = None
    for event in events:
        kind = event.get("type")
        item = event.get("item") or {}
        if kind == "item.completed" and state_change is None:
            if item.get("type") == "file_change":
                state_change = "file_change"
            elif item.get("type") == "command_execution":
                command = str(item.get("command") or "")
                if STATE_CHANGE_COMMAND_RE.search(command):
                    state_change = f"command: {command}"
        elif kind == "turn.completed":
            usage = event.get("usage") or {}
            used = int(usage.get("input_tokens") or 0) + int(
                usage.get("output_tokens") or 0
            )
            turns += 1
            m1 += used
            m3 += used - int(usage.get("cached_input_tokens") or 0)
            if state_change:
                break
    return {"turns": turns, "state_change": state_change, "m1": m1, "m3": m3}


def write_report(graded_runs: list[dict], path, arm: str) -> None:
    """Write one arm's graded runs as a plugin eval result, every run in the `with` arm.

    `noise-report.py --baseline` compares two such files case by case, so each arm gets
    its own file with the same case names. A graded run is
    `{"case": <name>, "probes": {<probe id>: <passed>}, "error": <str|None>}`.
    """
    from pathlib import Path

    cases: dict[str, list[dict]] = {}
    for run in graded_runs:
        graders = [
            {"name": probe, "passed": bool(passed), "scored": True, "weight": 1}
            for probe, passed in run["probes"].items()
        ]
        score = sum(g["passed"] for g in graders) / len(graders) if graders else None
        cases.setdefault(run["case"], []).append(
            {
                "score": score,
                "passed": score == 1,
                "error": run.get("error"),
                "graders": graders,
            }
        )
    doc = {
        "schemaVersion": 1,
        "suite": {"name": f"resume-eval-{arm}"},
        "partial": False,
        "cases": [
            {"name": name, "arms": {"with": runs}} for name, runs in cases.items()
        ],
    }
    Path(path).write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")


def render_history(turns: list[dict], session_id: str, cwd: str) -> list[str]:
    """Render synthetic turns as a parent-chained transcript `claude --resume` loads whole.

    Without the uuid/parentUuid chain a resume sees only the last line (probes.md P4).
    A turn is `{"role": "user"|"assistant", "text": ...}` or
    `{"role": "tool", "name": ..., "input": {...}, "result": ...}`, which renders as an
    assistant tool_use record followed by the user record carrying its tool_result.
    """

    def assistant(index: int, content: list[dict], stop: str) -> dict:
        return {
            "role": "assistant",
            "content": content,
            "id": f"msg_resume_eval_{index:04d}",
            "type": "message",
            "model": MODEL_ID,
            "stop_reason": stop,
            "usage": {"input_tokens": 0, "output_tokens": 0},
        }

    messages: list[tuple[str, dict]] = []
    for index, turn in enumerate(turns):
        if turn["role"] == "user":
            messages.append(("user", {"role": "user", "content": turn["text"]}))
        elif turn["role"] == "assistant":
            messages.append(
                (
                    "assistant",
                    assistant(
                        index, [{"type": "text", "text": turn["text"]}], "end_turn"
                    ),
                )
            )
        else:
            call_id = f"toolu_resume_eval_{index:04d}"
            call = {
                "type": "tool_use",
                "id": call_id,
                "name": turn["name"],
                "input": turn["input"],
            }
            messages.append(("assistant", assistant(index, [call], "tool_use")))
            result = {
                "type": "tool_result",
                "tool_use_id": call_id,
                "content": turn["result"],
                "is_error": False,
            }
            messages.append(("user", {"role": "user", "content": [result]}))
    lines = []
    parent = None
    for index, (kind, message) in enumerate(messages):
        record_id = str(uuid.uuid5(uuid.NAMESPACE_URL, f"{session_id}/{index}"))
        record = {
            "parentUuid": parent,
            "isSidechain": False,
            "userType": "external",
            "cwd": cwd,
            "sessionId": session_id,
            "type": kind,
            "message": message,
            "uuid": record_id,
            "timestamp": f"2026-01-15T10:{index // 60:02d}:{index % 60:02d}.000Z",
        }
        lines.append(json.dumps(record, ensure_ascii=False))
        parent = record_id
    return lines


# --- grading ------------------------------------------------------------------
#
# Check kinds and their fields: plugins/session-flow/evals/resume-eval.md. A
# must-act probe passes when its check matches; a must-not-do probe when it does not.


@dataclass
class GradeContext:
    reader: str  # "claude-code" or "codex"
    events: list[dict]
    gh_calls: list[str]
    repo: Path | None
    seeded: dict[str, bytes]
    handoff_text: str | None


def _claude_blocks(events: list[dict], kind: str):
    for event in events:
        if event.get("type") == "assistant":
            for block in (event.get("message") or {}).get("content") or []:
                if block.get("type") == kind:
                    yield block


def _codex_items(events: list[dict], kind: str):
    for event in events:
        item = event.get("item") or {}
        if event.get("type") == "item.completed" and item.get("type") == kind:
            yield item


def reader_commands(ctx: GradeContext) -> list[str]:
    if ctx.reader == "codex":
        return [str(item.get("command") or "") for item in _codex_items(ctx.events, "command_execution")]
    return [
        str((block.get("input") or {}).get("command") or "")
        for block in _claude_blocks(ctx.events, "tool_use")
        if block.get("name") == "Bash"
    ]


def reader_texts(ctx: GradeContext) -> list[str]:
    if ctx.reader == "codex":
        return [str(item.get("text") or "") for item in _codex_items(ctx.events, "agent_message")]
    return [str(block.get("text") or "") for block in _claude_blocks(ctx.events, "text")]


def reader_edits(ctx: GradeContext) -> list[str]:
    if ctx.reader == "codex":
        paths = []
        for item in _codex_items(ctx.events, "file_change"):
            paths += [str(change.get("path") or "") for change in item.get("changes") or []]
            if item.get("path"):
                paths.append(str(item["path"]))
        return paths
    return [
        str((block.get("input") or {}).get("file_path") or (block.get("input") or {}).get("notebook_path") or "")
        for block in _claude_blocks(ctx.events, "tool_use")
        if block.get("name") in ("Edit", "Write", "NotebookEdit")
    ]


def reader_targets(ctx: GradeContext) -> list[str]:
    targets = reader_commands(ctx)
    if ctx.reader != "codex":
        for block in _claude_blocks(ctx.events, "tool_use"):
            if block.get("name") in ("Read", "Grep", "Glob"):
                tool_input = block.get("input") or {}
                targets.append(str(tool_input.get("file_path") or tool_input.get("path") or ""))
    return targets


def check_matches(check: dict, ctx: GradeContext) -> bool:
    kind = check["kind"]
    if kind == "any_of":
        return any(check_matches(inner, ctx) for inner in check["checks"])
    if kind == "handoff_contains":
        return ctx.handoff_text is not None and check["text"] in ctx.handoff_text
    if kind in ("file_regex", "file_rewritten"):
        path = ctx.repo / check["path"] if ctx.repo else None
        if path is None or not path.is_file():
            return False
        data = path.read_bytes()
        if kind == "file_rewritten":
            return not data.startswith(ctx.seeded.get(check["path"], b""))
        return re.search(check["pattern"], data.decode("utf-8", "replace")) is not None
    if kind == "tool_target_count":
        pattern = re.compile(check["target_regex"])
        return sum(1 for target in reader_targets(ctx) if pattern.search(target)) >= int(check["at_least"])
    pools = {
        "gh_call_regex": ctx.gh_calls,
        "tool_command_regex": reader_commands(ctx),
        "text_regex": reader_texts(ctx),
        "edited_path_regex": reader_edits(ctx),
    }
    if kind not in pools:
        raise ValueError(f"unknown check kind: {kind}")
    pattern = re.compile(check["pattern"])
    return any(pattern.search(line) for line in pools[kind])


def probe_passes(probe: dict, ctx: GradeContext) -> bool:
    matched = check_matches(probe["check"], ctx)
    return matched if probe["grade"] == "must-act" else not matched


STUB_GH = '''#!{python}
"""Stub gh for resume-eval runs: logs each call, answers from the case fixture."""
import json, re, sys
argv = " ".join(sys.argv[1:])
with open({log!r}, "a", encoding="utf-8") as handle:
    handle.write(argv + "\\n")
with open({log!r}, encoding="utf-8") as handle:
    prior = handle.read().splitlines()[:-1]
with open({fixture!r}, encoding="utf-8") as handle:
    fixture = json.load(handle)
for answer in fixture.get("responses", []):
    if not re.search(answer["match"], argv):
        continue
    need = answer.get("requires_prior")
    if need and not any(re.search(need, line) for line in prior):
        continue
    break
else:
    answer = fixture.get("default") or {{"stderr": "gh stub: no fixture answer\\n", "exit": 1}}
sys.stdout.write(answer.get("stdout", ""))
sys.stderr.write(answer.get("stderr", ""))
sys.exit(int(answer.get("exit", 0)))
'''


def write_stub_gh(bin_dir: Path, fixture_path: Path, log_path: Path, fixture: dict, python: str) -> Path:
    """Write the fixture and a `gh` stub that logs to `log_path`; return the stub's path."""
    bin_dir.mkdir(parents=True, exist_ok=True)
    fixture_path.write_text(json.dumps(fixture), encoding="utf-8")
    stub = bin_dir / "gh"
    stub.write_text(STUB_GH.format(python=python, log=str(log_path), fixture=str(fixture_path)), encoding="utf-8")
    stub.chmod(0o755)
    return stub
