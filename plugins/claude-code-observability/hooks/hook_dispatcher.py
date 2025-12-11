#!/usr/bin/env python3
"""
Cross-platform hook dispatcher for Claude Code observability.

Usage: python hook_dispatcher.py <event_name>
Example: python hook_dispatcher.py stop

Reads JSON from stdin, logs to JSONL file, exits 0 always.
Never blocks Claude Code, never errors out.

Design principles:
1. Never block Claude Code - all exceptions caught, always exit 0
2. Fail silently - logging failures shouldn't impact user experience
3. Single entry point - one dispatcher handles all events
4. No dependencies - uses only Python standard library
5. Cross-platform by default - pathlib handles all path formats

Environment variables:
- CLAUDE_HOOK_LOG_EVENTS_ENABLED: Master enable (0/1, default: 0)
- CLAUDE_HOOK_LOG_{EVENT}_ENABLED: Per-event toggle (0/1, default: 1)
- CLAUDE_HOOK_LOG_VERBOSITY: minimal|summary|full (default: summary)
- CLAUDE_HOOK_LOG_ROTATION_ENABLED: Enable size-based rotation (0/1, default: 1)
- CLAUDE_HOOK_LOG_ROTATION_MAX_SIZE_MB: Max file size before rotation (default: 10)
- CLAUDE_HOOK_LOG_DEBUG: Show errors in stderr (0/1, default: 0)
"""
import sys
import json
import os
import time
from pathlib import Path
from datetime import datetime, timezone
from typing import Any, Dict, Optional

# Minimum Python version check - exit silently on old versions
if sys.version_info < (3, 6):
    sys.exit(0)

# Record start time immediately for duration tracking
_START_TIME = time.perf_counter()


def _is_truthy(value: Optional[str]) -> bool:
    """Check if environment variable value is truthy."""
    return value in ("1", "true", "True", "TRUE")


def _is_falsy(value: Optional[str]) -> bool:
    """Check if environment variable value is falsy."""
    return value in ("0", "false", "False", "FALSE")


def _get_verbosity() -> str:
    """Get verbosity level from environment, default to summary."""
    verbosity = os.environ.get("CLAUDE_HOOK_LOG_VERBOSITY", "summary").lower()
    if verbosity in ("minimal", "summary", "full"):
        return verbosity
    return "summary"


def _get_rotation_settings() -> tuple:
    """Get rotation settings from environment."""
    enabled = os.environ.get("CLAUDE_HOOK_LOG_ROTATION_ENABLED", "1")
    max_size_mb = os.environ.get("CLAUDE_HOOK_LOG_ROTATION_MAX_SIZE_MB", "10")
    try:
        max_size = int(max_size_mb) * 1024 * 1024  # Convert to bytes
    except ValueError:
        max_size = 10 * 1024 * 1024  # Default 10MB
    return _is_truthy(enabled) or enabled == "1", max_size


def _get_rotated_filename(log_dir: Path, base_date: str) -> Path:
    """
    Get the next available rotated filename.

    Returns: Path like events-2025-12-11-001.jsonl
    """
    counter = 1
    while True:
        rotated = log_dir / f"events-{base_date}-{counter:03d}.jsonl"
        if not rotated.exists():
            return rotated
        counter += 1
        if counter > 999:  # Safety limit
            return rotated


def _get_log_file(log_dir: Path, today: str) -> Path:
    """
    Get the appropriate log file, handling rotation if needed.

    Returns the file path to write to (may be rotated file).
    """
    rotation_enabled, max_size = _get_rotation_settings()
    base_file = log_dir / f"events-{today}.jsonl"

    if not rotation_enabled:
        return base_file

    # Check if base file exists and exceeds max size
    if base_file.exists():
        try:
            if base_file.stat().st_size >= max_size:
                return _get_rotated_filename(log_dir, today)
        except OSError:
            pass  # If we can't stat, just use base file

    return base_file


def _build_minimal_entry(
    event_name: str,
    hook_input: Dict[str, Any],
    duration_ms: float,
) -> Dict[str, Any]:
    """
    Build minimal log entry (~200 bytes).

    Contains: timestamp, event, session_id, tool_name (if applicable), duration_ms
    """
    entry = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "event": event_name,
        "session_id": hook_input.get("session_id", os.environ.get("CLAUDE_SESSION_ID", "unknown")),
        "duration_ms": round(duration_ms, 2),
    }

    # Add tool_name for tool-related events
    if "tool_name" in hook_input:
        entry["tool_name"] = hook_input["tool_name"]

    return entry


def _build_summary_entry(
    event_name: str,
    hook_input: Dict[str, Any],
    duration_ms: float,
) -> Dict[str, Any]:
    """
    Build summary log entry (~500 bytes).

    Contains: minimal fields + transcript_path, tool_use_id, cwd, permission_mode
    References transcripts instead of duplicating full payloads.
    """
    entry = _build_minimal_entry(event_name, hook_input, duration_ms)

    # Add reference fields (pointers to full data elsewhere)
    for key in ("transcript_path", "tool_use_id", "cwd", "permission_mode", "hook_event_name"):
        if key in hook_input:
            entry[key] = hook_input[key]

    # For PostToolUse, include success indicator without full response
    if event_name == "posttooluse" and "tool_response" in hook_input:
        response = hook_input["tool_response"]
        if isinstance(response, dict):
            entry["tool_success"] = response.get("success", not bool(response.get("stderr")))
            if "interrupted" in response:
                entry["interrupted"] = response["interrupted"]

    return entry


def _build_full_entry(
    event_name: str,
    hook_input: Dict[str, Any],
    duration_ms: float,
) -> Dict[str, Any]:
    """
    Build full log entry (1-50KB).

    Contains: complete input payload (current behavior).
    """
    entry = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "event": event_name,
        "session_id": os.environ.get("CLAUDE_SESSION_ID", "unknown"),
        "input": hook_input,
        "duration_ms": round(duration_ms, 2),
    }

    # Add environment context
    env_context = {}
    for key in ("CLAUDE_PROJECT_DIR", "CLAUDE_PLUGIN_ROOT", "CLAUDE_MODEL"):
        if key in os.environ:
            env_context[key] = os.environ[key]
    if env_context:
        entry["environment"] = env_context

    return entry


def main():
    """Main entry point - always exits 0."""
    try:
        # Get event name from args
        event_name = sys.argv[1] if len(sys.argv) > 1 else "unknown"

        # Check if logging is enabled (opt-in via environment variable)
        master_enabled = os.environ.get("CLAUDE_HOOK_LOG_EVENTS_ENABLED", "0")
        if not _is_truthy(master_enabled) and master_enabled != "1":
            # Logging not enabled - consume stdin and exit with status
            if not sys.stdin.isatty():
                sys.stdin.read()
            print(json.dumps({"systemMessage": "observability: disabled"}))
            sys.exit(0)

        # Check individual event toggle (allows disabling specific events)
        event_upper = event_name.upper().replace("-", "_")
        event_enabled = os.environ.get(f"CLAUDE_HOOK_LOG_{event_upper}_ENABLED", "1")
        if _is_falsy(event_enabled):
            if not sys.stdin.isatty():
                sys.stdin.read()
            print(json.dumps({"systemMessage": f"observability: {event_name} disabled"}))
            sys.exit(0)

        # Read stdin (hook input JSON)
        stdin_data = ""
        if not sys.stdin.isatty():
            stdin_data = sys.stdin.read()

        # Parse JSON safely
        try:
            hook_input = json.loads(stdin_data) if stdin_data.strip() else {}
        except json.JSONDecodeError:
            hook_input = {"raw": stdin_data}

        # Calculate duration (time from script start to now)
        duration_ms = (time.perf_counter() - _START_TIME) * 1000

        # Determine log directory using pathlib (cross-platform)
        project_dir = os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd())
        log_dir = Path(project_dir) / ".claude" / "logs" / "hooks"
        log_dir.mkdir(parents=True, exist_ok=True)

        # Build log entry based on verbosity level
        verbosity = _get_verbosity()
        if verbosity == "minimal":
            log_entry = _build_minimal_entry(event_name, hook_input, duration_ms)
        elif verbosity == "summary":
            log_entry = _build_summary_entry(event_name, hook_input, duration_ms)
        else:  # full
            log_entry = _build_full_entry(event_name, hook_input, duration_ms)

        # Get log file (handles rotation)
        today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        log_file = _get_log_file(log_dir, today)

        # Append to JSONL file
        with open(log_file, "a", encoding="utf-8") as f:
            f.write(json.dumps(log_entry, ensure_ascii=False, separators=(",", ":")) + "\n")

        # Output systemMessage for user visibility
        print(json.dumps({"systemMessage": f"observability: {event_name} logged"}))

    except Exception as e:
        # Swallow ALL errors - never block Claude Code
        # But optionally log for debugging when troubleshooting hooks
        if _is_truthy(os.environ.get("CLAUDE_HOOK_LOG_DEBUG", "0")):
            print(f"Hook dispatcher error: {e}", file=sys.stderr)

    # Always exit 0
    sys.exit(0)


if __name__ == "__main__":
    main()
