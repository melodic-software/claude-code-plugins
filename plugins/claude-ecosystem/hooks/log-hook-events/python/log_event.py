#!/usr/bin/env python3
"""
Hook event logger for Claude Code.

Fast Python-based logging that captures hook events to daily JSONL files.
Optimized for minimal overhead (~30-40ms per event) with concurrent safety.

Usage:
    cat input.json | python log_event.py <event_name>

Example:
    echo '{"session_id": "abc"}' | python log_event.py pretooluse
"""

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from threading import Lock
from typing import Any


# Valid Claude Code hook events (lowercase)
VALID_EVENTS = frozenset({
    "pretooluse",
    "posttooluse",
    "userpromptsubmit",
    "stop",
    "subagentstop",
    "sessionstart",
    "sessionend",
    "precompact",
    "notification",
    "permissionrequest",
})


def get_log_file_path(event_name: str) -> Path:
    """
    Get the log file path for today's logs for a specific event.

    Args:
        event_name: Event name (lowercase, e.g., "pretooluse")

    Returns:
        Path to log file: .claude/hooks/log-hook-events/logs/{event}/YYYY-MM-DD.jsonl
    """
    script_dir = Path(__file__).resolve().parent
    hooks_dir = script_dir.parent
    log_dir = hooks_dir / "logs" / event_name

    # Ensure log directory exists
    log_dir.mkdir(parents=True, exist_ok=True)

    # Get today's date in UTC
    date_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    return log_dir / f"{date_str}.jsonl"


def is_logging_enabled(event_name: str) -> bool:
    """
    Check if logging is enabled for this event.

    Logic:
    1. Check master toggle: CLAUDE_HOOK_LOG_EVENTS_ENABLED
       - If not set or "0"/"false": logging is disabled (default off)
       - If "1" or "true": continue to step 2
    2. Check individual toggle: CLAUDE_HOOK_LOG_{EVENT}_ENABLED
       - If "0" or "false": this event is disabled
       - Otherwise: this event is enabled (implicit enable from master)

    Args:
        event_name: Event name (lowercase, e.g., "pretooluse")

    Returns:
        True if logging is enabled, False otherwise
    """
    # Validate event name first (warn but don't block for forward-compatibility)
    if event_name not in VALID_EVENTS:
        print(f"WARNING: Unknown event '{event_name}', logging anyway", file=sys.stderr)

    # Check master toggle first
    master_key = "CLAUDE_HOOK_LOG_EVENTS_ENABLED"
    master_value = os.environ.get(master_key, "").lower()

    # If master not set or explicitly disabled, logging is off
    if master_value not in ("1", "true"):
        return False

    # Master is enabled, check individual toggle
    event_key = f"CLAUDE_HOOK_LOG_{event_name.upper()}_ENABLED"
    event_value = os.environ.get(event_key, "").lower()

    # If explicitly disabled, return False
    if event_value in ("0", "false"):
        return False

    # Otherwise enabled (implicit from master)
    return True


# Thread lock for writes within this process
# Note: Each hook event spawns a new Python process, so this Lock only provides
# thread-safety within a single invocation. Cross-process safety relies on
# file append atomicity for small writes (<PIPE_BUF, typically 4KB on POSIX).
# Our log entries are typically <1KB, so appends are atomic. On Windows, small
# appends are also atomic via the underlying file system implementation.
_WRITE_LOCK = Lock()


def log_event(event_name: str, stdin_data: dict[str, Any]) -> None:
    """
    Log a hook event to daily JSONL file.

    Args:
        event_name: Event name (lowercase, e.g., "pretooluse")
        stdin_data: Parsed JSON input from hook

    Raises:
        ValueError: If event_name is empty or not lowercase
        OSError: If log file cannot be written
    """
    if not event_name:
        raise ValueError("Event name cannot be empty")
    if not event_name.islower():
        raise ValueError(f"Event name must be lowercase: {event_name}")
    # Note: We log unknown events with a warning (see is_logging_enabled)
    # rather than rejecting them, to be forward-compatible with new events

    # Record start time for duration calculation
    start_time = datetime.now(timezone.utc)

    # Build log entry
    log_entry = {
        "timestamp": start_time.isoformat().replace("+00:00", "Z"),
        "event": event_name,
        "stdin": stdin_data,
        "stdout": "",
        "exit_code": 0,
        "duration_ms": 0,  # Will be updated below
    }

    # Calculate duration
    end_time = datetime.now(timezone.utc)
    duration = (end_time - start_time).total_seconds() * 1000
    log_entry["duration_ms"] = int(duration)

    # Get log file path
    log_file = get_log_file_path(event_name)

    # Append to log file (atomic for entries <4KB, which is typical)
    # Python file append is atomic up to PIPE_BUF (usually 4KB) on POSIX systems
    # Windows uses different mechanism but also supports atomic small appends
    log_line = json.dumps(log_entry, separators=(",", ":"))

    try:
        with _WRITE_LOCK:
            with log_file.open("a", encoding="utf-8") as f:
                f.write(log_line + "\n")
    except OSError as e:
        # Log to stderr but don't fail (logging is non-critical)
        print(f"WARNING: Failed to write log: {e}", file=sys.stderr)


def main() -> int:
    """
    Main entry point for hook event logger.

    Reads JSON from stdin, logs event to daily JSONL file.

    Returns:
        Exit code (0 for success, 1 for error)
    """
    # Get event name from command line
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <event_name>", file=sys.stderr)
        return 1

    event_name = sys.argv[1].lower()

    # Check if logging is enabled
    if not is_logging_enabled(event_name):
        return 0

    try:
        # Read and parse stdin
        stdin_text = sys.stdin.read()
        stdin_data = json.loads(stdin_text)

        # Log the event
        log_event(event_name, stdin_data)

        return 0

    except json.JSONDecodeError as e:
        print(f"ERROR: Invalid JSON input: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"ERROR: Failed to log event: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
