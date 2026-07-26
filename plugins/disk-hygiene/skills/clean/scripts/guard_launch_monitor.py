#!/usr/bin/env python3
"""Surface silent ``destructive_guard.py`` launch/runtime failures (#1416).

A `PreToolUse` hook that fails to launch, or launches and then exits
non-zero, denies nothing — Claude Code treats a non-blocking hook result as
approval and lets the guarded Bash/PowerShell command proceed ungated (the
0.6.3 fail-open shape; see ``reference/safety-model.md``). From outside the
harness "the guard denied nothing because it approved" and "the guard denied
nothing because it never ran, or ran and silently died" look identical. This
module closes that observability gap for one specific, narrow signal: the
engine-gate guard invocation (``destructive_guard.py``) recorded as a
``hook_non_blocking_error`` attachment in the session transcript.

This is a *detector*, not a guard, and it must never behave like one:

- It never emits ``permissionDecision`` and never blocks a tool call — it is
  registered on the ``Stop`` event (see below), which has no blocking
  vocabulary for this purpose to begin with; the only output it ever emits is
  ``{"systemMessage": "..."}``.
- On any failure to read or parse the transcript it exits 0 with no stdout.
  A detector that fails loudly for its own sake is exactly the kind of
  second-order fragility this issue exists to avoid: it must never itself
  become the reason a turn is blocked or a tool call denied.
- It is a separate process from the guard, deliberately: a guard that cannot
  launch cannot report that it did not launch, so the detector cannot be
  wired through the guard's own code path. It imports nothing from
  ``destructive_guard.py`` or ``lib/`` — stdlib only — so its own failure
  surface stays near zero.

Why ``Stop``, not ``PreToolUse``/``PostToolUse``
=================================================
This repo has already paid for a hook that runs on every matching tool call:
``docs/adr/0004-rightsize-instruction-surfaces-by-incumbent-first-arbitration.md``
documents D-12, a guardrails ``PreToolUse`` hook that cost 12-19s p50 on every
single Bash call across roughly 1,464 runs in six days. A new hook wired to
``PreToolUse``/``PostToolUse`` with a Bash/PowerShell matcher would repeat
that risk class on every guarded command, forever, to catch a failure that -
by construction - is already sitting in the transcript file by the time the
guarded command's hook step in the docs' three-cadence classification
(once-per-session / once-per-turn / once-per-tool-call) completes. ``Stop``
fires once per turn: the guard, if it ran, ran synchronously before the
guarded command executed, so its failure record (if any) is already appended
to the transcript well before the turn ends. Once-per-turn cadence catches
the failure just as promptly as once-per-tool-call would, at a small
fraction of the invocation count.

Bounded-cost transcript read
=============================
Transcript files grow for the life of a session and are written
asynchronously (may lag the in-memory conversation — see the hooks docs).
Reading the whole file on every ``Stop`` would scale invocation cost with
session length, the same shape of problem D-12 created a different way. This
module instead seeks to the last ``_MAX_TAIL_BYTES`` of the file, discards
the (likely-truncated) first partial line, and parses what remains — cost is
O(cap), not O(session length), regardless of how large the transcript gets.
Once a warning has fired for a session, the once-per-session marker (see
below) short-circuits *before* the read, so the amortized per-turn cost for
the rest of a long session is a single stat() of a small marker file.

Once-per-session marker
========================
Keyed by the hook's own ``session_id`` input field (never anything found
*inside* transcript records — a transcript can carry attachment records
whose own ``session_id`` field differs from the session that produced the
file; only the hook's own stdin input names the current session reliably).
Primary location is a marker file under ``${CLAUDE_PLUGIN_DATA}`` (passed
via ``--data-root``); this is a plugin-level ``hooks/hooks.json``
registration, so unlike a skill-frontmatter hook, ``${CLAUDE_PLUGIN_DATA}``
substitutes directly here — no need for ``destructive_guard.py``'s
``--plugin-root`` derivation dance (a literal unsubstituted
``${CLAUDE_PLUGIN_DATA}`` token is still treated as absent, matching that
module's placeholder idiom). Fallback is a subdirectory under
``tempfile.gettempdir()``. The bookkeeping degrades toward *re-warning*,
never toward silence: if both the primary and fallback marker writes fail,
the warning is still emitted this run rather than suppressed — over-warning
is the safe failure direction for a module that exists specifically to kill
a silent-suppression defect class.
"""

from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path

_MAX_TAIL_BYTES = 2_000_000

_GUARD_COMMAND_SUBSTRING = "destructive_guard.py"
_GUARD_DISPLAY_NAME = "destructive_guard.py"

_DATA_ROOT_FLAG = "--data-root"
_CLAUDE_PLUGIN_DATA_ENV = "CLAUDE_PLUGIN_DATA"
_DATA_ROOT_PLACEHOLDER = f"${{{_CLAUDE_PLUGIN_DATA_ENV}}}"

_MARKER_DIRNAME = "guard-launch-monitor"
_STDERR_TRUNCATE_CHARS = 300


def _argv_flag_value(argv: list[str], flag: str) -> str | None:
    for index, item in enumerate(argv):
        if item == flag and index + 1 < len(argv):
            return argv[index + 1]
        if item.startswith(flag + "="):
            return item.split("=", 1)[1]
    return None


def _resolve_data_root(argv: list[str]) -> str | None:
    """Resolve the plugin's persistent data root, or None if unavailable.

    A literal unsubstituted ``${CLAUDE_PLUGIN_DATA}`` placeholder is treated
    as absent, matching ``destructive_guard.py``'s placeholder idiom (see
    module docstring) — this module does not import that idiom, only mirrors
    it, per the issue's stdlib-only requirement.
    """
    direct = _argv_flag_value(argv, _DATA_ROOT_FLAG)
    if direct and direct != _DATA_ROOT_PLACEHOLDER:
        return direct
    env_value = os.environ.get(_CLAUDE_PLUGIN_DATA_ENV)
    if env_value and env_value != _DATA_ROOT_PLACEHOLDER:
        return env_value
    return None


def _marker_path_candidates(data_root: str | None, session_id: str) -> list[Path]:
    safe_session = "".join(
        ch if (ch.isalnum() or ch in "-_") else "_" for ch in session_id
    ) or "unknown-session"
    candidates: list[Path] = []
    if data_root:
        candidates.append(
            Path(data_root) / _MARKER_DIRNAME / f"{safe_session}.warned"
        )
    candidates.append(
        Path(tempfile.gettempdir())
        / "disk-hygiene-guard-launch-monitor"
        / f"{safe_session}.warned"
    )
    return candidates


def _already_warned(marker_paths: list[Path]) -> bool:
    for path in marker_paths:
        try:
            if path.is_file():
                return True
        except OSError:
            continue
    return False


def _write_marker(marker_paths: list[Path]) -> None:
    """Best-effort write. Failure here must never suppress a real finding."""
    for path in marker_paths:
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("1", encoding="utf-8")
            return
        except OSError:
            continue


def _read_tail(transcript_path: str) -> str:
    path = Path(transcript_path)
    size = path.stat().st_size
    with path.open("rb") as handle:
        if size > _MAX_TAIL_BYTES:
            offset = size - _MAX_TAIL_BYTES
            # A newline immediately before the window means the window already
            # starts on a record boundary; discarding then would throw away a
            # whole record, which can be the only guard failure in the tail.
            handle.seek(offset - 1)
            starts_mid_record = handle.read(1) != b"\n"
            if starts_mid_record:
                handle.readline()  # discard the truncated partial first line
        raw = handle.read()
    return raw.decode("utf-8", errors="replace")


def _iter_guard_failures(transcript_text: str):
    for line in transcript_text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            record = json.loads(line)
        except (json.JSONDecodeError, ValueError):
            continue
        if not isinstance(record, dict):
            continue
        if record.get("type") != "attachment":
            continue
        attachment = record.get("attachment")
        if not isinstance(attachment, dict):
            continue
        if attachment.get("type") != "hook_non_blocking_error":
            continue
        command = attachment.get("command")
        if not isinstance(command, str) or _GUARD_COMMAND_SUBSTRING not in command:
            continue
        yield record, attachment


def _format_stderr(stderr: object) -> str:
    if not isinstance(stderr, str) or not stderr.strip():
        return "(no stderr output)"
    text = stderr.strip()
    if len(text) > _STDERR_TRUNCATE_CHARS:
        return text[:_STDERR_TRUNCATE_CHARS] + "... (truncated)"
    return text


def _build_message(failures: list[tuple[dict, dict]]) -> str:
    count = len(failures)
    # Records are scanned in file order (chronological); the last match is
    # the most recent failure.
    _, latest = failures[-1]
    exit_code = latest.get("exitCode")
    duration_ms = latest.get("durationMs")
    stderr_text = _format_stderr(latest.get("stderr"))
    plural = "s" if count != 1 else ""
    return (
        f"disk-hygiene: {_GUARD_DISPLAY_NAME} failed to run or exited "
        f"non-zero {count} time{plural} this session and its failure(s) were "
        "not visible as a denial. Most recent failure: "
        f"exitCode: {exit_code}, durationMs: {duration_ms}, stderr: {stderr_text} "
        "This means destructive-action review may not have been enforced for "
        "the guarded command(s) in question. This detector covers only "
        f"{_GUARD_DISPLAY_NAME}'s own command string in this session's "
        "transcript; it does not cover repo-hygiene's guard (verified "
        "working separately) and does not retroactively scan past sessions."
    )


def _run(hook_input: dict, data_root: str | None) -> str | None:
    transcript_path = hook_input.get("transcript_path")
    session_id = hook_input.get("session_id") or "unknown-session"
    marker_paths = _marker_path_candidates(data_root, str(session_id))
    if _already_warned(marker_paths):
        return None
    if not transcript_path or not isinstance(transcript_path, str):
        return None
    transcript_text = _read_tail(transcript_path)
    failures = list(_iter_guard_failures(transcript_text))
    if not failures:
        return None
    message = _build_message(failures)
    _write_marker(marker_paths)
    return message


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    try:
        data_root = _resolve_data_root(argv)
        raw_input = sys.stdin.read()
        hook_input = json.loads(raw_input) if raw_input.strip() else {}
        if not isinstance(hook_input, dict):
            return 0
        message = _run(hook_input, data_root)
        if message:
            print(json.dumps({"systemMessage": message}))
        return 0
    except BaseException:  # noqa: BLE001 - detector must never fail loudly
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
