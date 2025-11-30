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
import re
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


def _parse_yaml_bool(value: str) -> bool | None:
    """Parse YAML boolean values. Returns None if not a boolean."""
    value = value.strip().lower()
    if value in ("true", "yes", "on", "1"):
        return True
    if value in ("false", "no", "off", "0"):
        return False
    return None


def _get_yaml_value(config_text: str, key_path: str) -> str | None:
    """
    Extract a value from YAML text using simple regex parsing.

    Supports dot notation for nested keys (e.g., "events.pretooluse.enabled").
    Does not require a YAML library.

    Args:
        config_text: Full YAML file contents
        key_path: Dot-separated key path

    Returns:
        String value if found, None otherwise
    """
    keys = key_path.split(".")
    lines = config_text.split("\n")

    # Track indentation levels as we descend into nested keys
    current_indent = -1
    looking_for_idx = 0

    for line in lines:
        # Skip empty lines and comments
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        # Calculate indentation (spaces before content)
        indent = len(line) - len(line.lstrip())

        # If we moved to same or lower indent, reset search if not at root
        if indent <= current_indent and looking_for_idx > 0:
            # We've exited the section we were searching in
            looking_for_idx = 0
            current_indent = -1

        key_to_find = keys[looking_for_idx]

        # Check for key match (handle "key:" and "key: value" patterns)
        key_pattern = rf"^{re.escape(key_to_find)}\s*:\s*(.*?)$"
        match = re.match(key_pattern, stripped)

        if match:
            if looking_for_idx == len(keys) - 1:
                # Found the final key - return its value
                value = match.group(1).strip()
                # Remove inline comments
                if "#" in value:
                    value = value.split("#")[0].strip()
                return value if value else None
            else:
                # Found intermediate key - descend into it
                looking_for_idx += 1
                current_indent = indent

    return None


def is_logging_enabled(event_name: str) -> bool:
    """
    Check if logging is enabled for this event.

    Uses process-local caching via environment variables to avoid repeated
    config file reads within a single invocation. Since each hook event
    spawns a new Python process, caching doesn't persist across events -
    config changes take effect on the next event automatically (no TTL needed).

    Args:
        event_name: Event name (lowercase, e.g., "pretooluse")

    Returns:
        True if logging is enabled, False otherwise
    """
    # Validate event name first (warn but don't block for forward-compatibility)
    if event_name not in VALID_EVENTS:
        print(f"WARNING: Unknown event '{event_name}', logging anyway", file=sys.stderr)

    # Check process-local cache (only persists within this invocation)
    cache_key = f"HOOK_LOG_{event_name.upper()}_ENABLED"
    cached_value = os.environ.get(cache_key)

    if cached_value is not None:
        return cached_value == "1"

    # Load config (simple YAML parsing - just need enabled flags)
    script_dir = Path(__file__).resolve().parent
    config_file = script_dir.parent / "config.yaml"

    if not config_file.exists():
        # Default to enabled if config missing
        os.environ[cache_key] = "1"
        return True

    try:
        config_text = config_file.read_text(encoding="utf-8")

        # Check master enabled flag (top-level "enabled: false")
        master_enabled = _get_yaml_value(config_text, "enabled")
        if master_enabled is not None:
            parsed = _parse_yaml_bool(master_enabled)
            if parsed is False:
                os.environ[cache_key] = "0"
                return False

        # Check event-specific enabled flag (events.<event_name>.enabled)
        event_enabled = _get_yaml_value(config_text, f"events.{event_name}.enabled")
        if event_enabled is not None:
            parsed = _parse_yaml_bool(event_enabled)
            if parsed is False:
                os.environ[cache_key] = "0"
                return False

        # Default to enabled
        os.environ[cache_key] = "1"
        return True

    except Exception as e:
        # On any error, default to enabled (logging is non-critical)
        print(f"WARNING: Config read error ({e}), defaulting to enabled", file=sys.stderr)
        os.environ[cache_key] = "1"
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
