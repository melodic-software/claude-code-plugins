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
  ``destructive_guard.py`` — stdlib only plus the sibling ``lib/hook_telemetry``
  module (the fleet's native Python telemetry emitter; #1505) — so its own
  failure surface stays near zero.

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

Incremental transcript read
============================
Transcript files grow for the life of a session and are written
asynchronously (may lag the in-memory conversation — see the hooks docs).
Reading the whole file on every ``Stop`` would scale invocation cost with
session length, the same shape of problem D-12 created a different way. So
the read is incremental: a per-session cursor (``<session>.cursor`` beside the
marker, holding ``b<offset>\\n<transcript_path>\\n``) records how far a clean
scan got, and the next ``Stop`` seeks there and reads only what was appended
since. The shape follows claude-ops ``hook-failure-audit.sh`` (#4408).

The first scan of a session, and any reset, reads the WHOLE file: a guard
failure anywhere in it must still warn (#1514), so there is no tail cap. That
cold read happens once per session, and a byte-level pre-filter skips the JSON
parse of every line that cannot be a failure record.

Every doubt about the cursor resolves toward a cold rescan, never toward
silence: a missing, unreadable or malformed cursor (including the offset below
2 or a non-canonical number), a cursor naming another transcript path, a file
now shorter than the offset, or no newline just before the offset (the file
was truncated or replaced). The one case that gets past that check is a
same-path replacement with a newline at exactly the old offset; its first
``offset`` bytes are never read. A rescan cannot re-warn: the marker decides.

The cursor covers complete lines only. A final line with no newline is still
scanned this turn but not counted, so the next ``Stop`` reads it again once
the harness has finished writing it. And the cursor advances only past a scan
that found NO failure: a failure warns and writes the marker, and if the
marker cannot be written the next ``Stop`` rescans the same bytes and re-warns
with the same count, exactly as the whole-file read did.

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
import re
import sys
import tempfile
import time
from pathlib import Path

_LIB_DIR = Path(__file__).resolve().parents[3] / "lib"
if str(_LIB_DIR) not in sys.path:
    sys.path.insert(0, str(_LIB_DIR))

import guard_decision_log  # noqa: E402  (path set above; bounded local record)
import hook_telemetry  # noqa: E402  (path set above; stdlib-only telemetry emitter)

_FAILURE_NEEDLE = b"hook_non_blocking_error"
_CURSOR_PATTERN = re.compile(r"b([1-9][0-9]{0,14})")

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


def _marker_path_candidates(
    data_root: str | None, session_id: str, suffix: str = ".warned"
) -> list[Path]:
    safe_session = (
        "".join(ch if (ch.isalnum() or ch in "-_") else "_" for ch in session_id)
        or "unknown-session"
    )
    candidates: list[Path] = []
    if data_root:
        candidates.append(Path(data_root) / _MARKER_DIRNAME / f"{safe_session}{suffix}")
    candidates.append(
        Path(tempfile.gettempdir())
        / "disk-hygiene-guard-launch-monitor"
        / f"{safe_session}{suffix}"
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


def _read_cursor(cursor_paths: list[Path], transcript_path: str) -> int:
    """Return the offset a clean scan of this transcript reached, or 0."""
    for path in cursor_paths:
        try:
            text = path.read_text(encoding="utf-8")
        except OSError:
            continue
        offset, _, rest = text.partition("\n")
        match = _CURSOR_PATTERN.fullmatch(offset)
        if not match or rest != transcript_path + "\n":
            return 0
        return int(match.group(1))
    return 0


def _write_cursor(cursor_paths: list[Path], offset: int, transcript_path: str) -> None:
    """Best-effort: a cursor that cannot be written only costs a rescan."""
    for path in cursor_paths:
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(f"b{offset}\n{transcript_path}\n", encoding="utf-8")
            return
        except OSError:
            continue


def _read_new(transcript_path: str, cursor: int) -> tuple[bytes, int]:
    """Return the bytes to scan and the offset the next clean scan may resume at.

    Starts at ``cursor`` when the byte before it is still a newline, else at 0.
    The returned offset stops after the last newline read.
    """
    with open(transcript_path, "rb") as handle:
        start = 0
        if cursor >= 2:
            handle.seek(cursor - 1)
            if handle.read(1) == b"\n":
                start = cursor
        handle.seek(start)
        data = handle.read()
    return data, start + data.rfind(b"\n") + 1


def _iter_guard_failures(data: bytes):
    """Yield the ``hook_non_blocking_error`` attachment of each guard failure.

    Lines without the attachment type's name cannot match, so they skip the
    decode and the JSON parse.
    """
    if _FAILURE_NEEDLE not in data:
        return
    for raw in data.split(b"\n"):
        if _FAILURE_NEEDLE not in raw:
            continue
        line = raw.decode("utf-8", errors="replace").strip()
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
        yield attachment


def _format_stderr(stderr: object) -> str:
    if not isinstance(stderr, str) or not stderr.strip():
        return "(no stderr output)"
    text = stderr.strip()
    if len(text) > _STDERR_TRUNCATE_CHARS:
        return text[:_STDERR_TRUNCATE_CHARS] + "... (truncated)"
    return text


def _build_message(failures: list[dict]) -> str:
    count = len(failures)
    # Records are scanned in file order (chronological); the last match is
    # the most recent failure.
    latest = failures[-1]
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
        "transcript; it does not cover repo-hygiene's guard and does not "
        "retroactively scan past sessions."
    )


def _audit_fields(failures: list[dict], session_id: str) -> dict:
    """Structured detail for the local decision record.

    Deliberately separate from ``telemetry_data``: the telemetry envelope's
    contents are a published contract for a configured sink, and the local
    record is a different consumer with a different need (enough to explain one
    failure without the session's transcript), so neither shapes the other.
    """
    latest = failures[-1]
    return {
        "failure_count": len(failures),
        "session_id": session_id,
        "exit_code": latest.get("exitCode"),
        "duration_ms": latest.get("durationMs"),
        "stderr": _format_stderr(latest.get("stderr")),
    }


def _record_not_run(data_root: str | None, audit_fields: dict) -> None:
    """Record that the guard produced no decision at all for this session.

    The third state the guard itself structurally cannot write: a hook that
    failed to launch, or launched and exited non-zero, records nothing from
    inside its own process. Written once per session, at the same moment the
    warning is emitted and before the suppression marker lands, so the record
    follows the warning's own once-per-session cadence.
    """
    try:
        guard_decision_log.record(
            data_root,
            hook="guard-launch-monitor",
            decision=guard_decision_log.DECISION_NOT_RUN,
            rule="hook-non-blocking-error",
            tool="",
            extra=audit_fields,
        )
    except BaseException:  # noqa: BLE001 - a detector must never fail loudly
        pass


def _run(
    hook_input: dict, data_root: str | None
) -> tuple[str | None, list[Path] | None, str | None, dict[str, object], dict]:
    """Return warning text, marker paths, telemetry status, telemetry data, audit.

    ``telemetry_status`` is ``None`` when no envelope should be emitted (a
    pre-evaluation short-circuit). Recording the marker is the caller's job,
    deliberately: the marker suppresses every later ``Stop`` in the session, so
    it must not be written until the warning has actually left the process.
    """
    transcript_path = hook_input.get("transcript_path")
    session_id = hook_input.get("session_id") or "unknown-session"
    marker_paths = _marker_path_candidates(data_root, str(session_id))
    if _already_warned(marker_paths):
        return None, None, None, {}, {}
    if not transcript_path or not isinstance(transcript_path, str):
        return None, None, None, {}, {}
    cursor_paths = _marker_path_candidates(data_root, str(session_id), ".cursor")
    data, resume_at = _read_new(
        transcript_path, _read_cursor(cursor_paths, transcript_path)
    )
    failures = list(_iter_guard_failures(data))
    if not failures:
        _write_cursor(cursor_paths, resume_at, transcript_path)
        return None, None, "ok", {}, {}
    return (
        _build_message(failures),
        marker_paths,
        "error",
        {"failure_count": len(failures)},
        _audit_fields(failures, str(session_id)),
    )


def main(argv: list[str] | None = None) -> int:
    start = time.perf_counter()
    argv = sys.argv[1:] if argv is None else argv
    try:
        data_root = _resolve_data_root(argv)
        raw_input = sys.stdin.read()
        hook_input = json.loads(raw_input) if raw_input.strip() else {}
        if not isinstance(hook_input, dict):
            return 0
        message, marker_paths, telemetry_status, telemetry_data, audit_fields = _run(
            hook_input, data_root
        )
        if telemetry_status is not None:
            hook_telemetry.emit(
                "guard-launch-monitor",
                "Stop",
                telemetry_status,
                start,
                telemetry_data,
                os.environ.get("CLAUDE_PROJECT_DIR"),
            )
        if message:
            print(json.dumps({"systemMessage": message}))
            sys.stdout.flush()
            _record_not_run(data_root, audit_fields)
            if marker_paths is not None:
                _write_marker(marker_paths)
        return 0
    except BaseException:  # noqa: BLE001 - detector must never fail loudly
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
