#!/usr/bin/env python3
"""Measure how long a session was stopped, from transcript timestamps.

Reads a session transcript (JSONL) and prints one JSON object:

  last_assistant  ISO-8601 time of the last assistant entry that is not an error
                  and precedes the resuming prompt
  limit_or_error  ISO-8601 time of the last limit or error entry before the
                  resuming prompt, or null
  now             ISO-8601 time of the measurement
  stop_at         the instant the stop began: limit_or_error when it is not
                  before last_assistant, else last_assistant
  gap_seconds     seconds from stop_at to now (never negative)
  gap             the same, as a human-readable duration such as 1d 2h 3m 4s

An entry counts as a limit or error entry when it sets ``isApiErrorMessage``,
carries a top-level ``error`` key, or is a ``system`` entry whose ``level`` is
``error``. The resuming prompt is the latest user entry that is not a tool result
(not meta, compaction summary or sidechain) that has an assistant entry before it;
entries at or after it belong to the resumed turn and are ignored, so the turn's
own work, including its own error entries, never shortens the gap. Without such a
prompt every entry counts. Timestamps may carry any offset or ``Z``; a timestamp
without an offset is read as UTC.

Scope: the measurement supports only the live resumed session's transcript, read
after the resuming prompt; a stopped transcript that no prompt has resumed yet is
out of scope.

Exit codes:
  0 - measured; the JSON object is on stdout
  2 - the transcript is missing, unreadable, empty, or holds no assistant
      entry with a usable timestamp; the gap is unknown (message on stderr)
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


def _parse_instant(value: object) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def _is_error(entry: dict) -> bool:
    if entry.get("isApiErrorMessage") or entry.get("error"):
        return True
    return entry.get("type") == "system" and entry.get("level") == "error"


def _is_prompt(entry: dict) -> bool:
    if entry.get("type") != "user":
        return False
    if entry.get("isMeta") or entry.get("isCompactSummary") or entry.get("isSidechain"):
        return False
    message = entry.get("message")
    content = message.get("content") if isinstance(message, dict) else None
    if isinstance(content, list):
        return not any(
            isinstance(part, dict) and part.get("type") == "tool_result"
            for part in content
        )
    return True


def _format_gap(seconds: int) -> str:
    days, rest = divmod(seconds, 86400)
    hours, rest = divmod(rest, 3600)
    minutes, secs = divmod(rest, 60)
    parts = [
        f"{amount}{unit}"
        for amount, unit in ((days, "d"), (hours, "h"), (minutes, "m"))
        if amount
    ]
    parts.append(f"{secs}s")
    return " ".join(parts)


def measure(path: Path, now: datetime) -> dict:
    """Return the measurement, or raise ValueError when the gap is unknown."""
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError) as exc:
        raise ValueError(f"cannot read transcript {path}: {exc}") from exc
    assistants: list[datetime] = []
    errors: list[datetime] = []
    prompts: list[datetime] = []
    for line in lines:
        if not line.strip():
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(entry, dict):
            continue
        stamp = _parse_instant(entry.get("timestamp"))
        if stamp is None:
            continue
        if _is_error(entry):
            errors.append(stamp)
        elif entry.get("type") == "assistant":
            assistants.append(stamp)
        elif _is_prompt(entry):
            prompts.append(stamp)
    boundary: datetime | None = None
    for prompt in sorted(prompts, reverse=True):
        if any(stamp < prompt for stamp in assistants):
            boundary = prompt
            break
    if boundary is not None:
        assistants = [stamp for stamp in assistants if stamp < boundary]
        errors = [stamp for stamp in errors if stamp < boundary]
    last_assistant = max(assistants, default=None)
    last_error = max(errors, default=None)
    if last_assistant is None:
        raise ValueError(
            f"transcript {path} has no assistant entry with a usable timestamp"
        )
    if last_error is not None and last_error >= last_assistant:
        stop_at = last_error
    else:
        stop_at = last_assistant
    seconds = max(0, int((now - stop_at).total_seconds()))
    return {
        "last_assistant": last_assistant.isoformat(),
        "limit_or_error": last_error.isoformat() if last_error else None,
        "now": now.isoformat(),
        "stop_at": stop_at.isoformat(),
        "gap_seconds": seconds,
        "gap": _format_gap(seconds),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("transcript", help="Path to the session transcript (JSONL)")
    parser.add_argument(
        "--now",
        help="ISO-8601 override for tests (must include offset or Z)",
    )
    args = parser.parse_args(argv)
    if args.now:
        now = _parse_instant(args.now)
        if now is None:
            print(f"unparsed --now: {args.now!r}", file=sys.stderr)
            return 2
    else:
        now = datetime.now(timezone.utc)
    try:
        result = measure(Path(args.transcript), now)
    except ValueError as exc:
        print(f"gap-unknown: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
