#!/usr/bin/env python3
"""
Hook event logger for Claude Code.

Fast Python-based logging that captures hook events to daily JSONL files.
Supports configurable verbosity levels, size-based rotation, and workflow correlation.

Usage:
    cat input.json | python log_event.py <event_name>

Example:
    echo '{"session_id": "abc"}' | python log_event.py pretooluse

Configuration:
    - config.yaml in hooks/log-hook-events/ directory
    - Environment variables override YAML settings
    - See config.yaml for full documentation
"""

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from threading import Lock
from typing import Any, Optional

# Optional YAML support - graceful degradation if not installed
try:
    import yaml
    YAML_AVAILABLE = True
except ImportError:
    YAML_AVAILABLE = False


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

# Thread lock for writes within this process
_WRITE_LOCK = Lock()

# Configuration cache (loaded once per invocation)
_config_cache: Optional[dict] = None


# =============================================================================
# Path Resolution
# =============================================================================


def get_hooks_dir() -> Path:
    """Get the hooks/log-hook-events directory."""
    return Path(__file__).resolve().parent.parent


def get_log_dir() -> Path:
    """Get the logs directory."""
    return get_hooks_dir() / "logs"


def get_config_path() -> Path:
    """Get path to config.yaml file."""
    return get_hooks_dir() / "config.yaml"


# =============================================================================
# Configuration
# =============================================================================


def _get_default_config() -> dict:
    """Return default configuration."""
    return {
        "logging": {
            "enabled": True,
            "verbosity": "summary",
            "rotation": {
                "enabled": True,
                "max_file_size_mb": 10
            },
            "retention": {
                "max_age_days": 30
            },
            "events": {}
        }
    }


def _deep_merge(base: dict, override: dict) -> None:
    """Deep merge override dict into base dict (modifies base in-place)."""
    for key, value in override.items():
        if key in base and isinstance(base[key], dict) and isinstance(value, dict):
            _deep_merge(base[key], value)
        else:
            base[key] = value


def _set_nested(d: dict, path: list, value: Any) -> None:
    """Set a value in a nested dict using a path list."""
    for key in path[:-1]:
        d = d.setdefault(key, {})
    d[path[-1]] = value


def _apply_env_overrides(config: dict) -> None:
    """Apply environment variable overrides to config."""
    env_mappings = [
        ("CLAUDE_HOOK_LOG_EVENTS_ENABLED", ["logging", "enabled"],
         lambda x: x.lower() in ("1", "true")),
        ("CLAUDE_HOOK_LOG_VERBOSITY", ["logging", "verbosity"], str),
        ("CLAUDE_HOOK_LOG_ROTATION_ENABLED", ["logging", "rotation", "enabled"],
         lambda x: x.lower() in ("1", "true")),
        ("CLAUDE_HOOK_LOG_ROTATION_MAX_SIZE_MB", ["logging", "rotation", "max_file_size_mb"], int),
        ("CLAUDE_HOOK_LOG_RETENTION_MAX_AGE_DAYS", ["logging", "retention", "max_age_days"], int),
    ]

    for env_key, path, converter in env_mappings:
        env_value = os.environ.get(env_key)
        if env_value is not None:
            try:
                _set_nested(config, path, converter(env_value))
            except (ValueError, TypeError) as e:
                print(f"WARNING: Invalid value for {env_key}: {e}", file=sys.stderr)

    # Per-event verbosity overrides
    for event in VALID_EVENTS:
        env_key = f"CLAUDE_HOOK_LOG_EVENT_{event.upper()}_VERBOSITY"
        env_value = os.environ.get(env_key)
        if env_value is not None:
            if "events" not in config["logging"]:
                config["logging"]["events"] = {}
            if event not in config["logging"]["events"]:
                config["logging"]["events"][event] = {}
            config["logging"]["events"][event]["verbosity"] = env_value


def load_config() -> dict:
    """
    Load configuration from YAML file with environment variable overrides.

    Priority (highest to lowest):
    1. Environment variables
    2. config.yaml
    3. Default values

    Returns:
        Configuration dictionary
    """
    global _config_cache

    if _config_cache is not None:
        return _config_cache

    # Start with defaults
    config = _get_default_config()

    # Load from YAML file if exists and yaml is available
    config_path = get_config_path()
    if YAML_AVAILABLE and config_path.exists():
        try:
            with open(config_path, "r", encoding="utf-8") as f:
                yaml_config = yaml.safe_load(f)
                if yaml_config:
                    _deep_merge(config, yaml_config)
        except Exception as e:
            print(f"WARNING: Failed to load config.yaml: {e}", file=sys.stderr)

    # Apply environment variable overrides
    _apply_env_overrides(config)

    _config_cache = config
    return config


def get_verbosity(event_name: str, config: dict) -> str:
    """
    Get verbosity level for a specific event.

    Args:
        event_name: Event name (lowercase)
        config: Configuration dictionary

    Returns:
        Verbosity level: "minimal", "summary", or "full"
    """
    # Check per-event override first
    event_config = config.get("logging", {}).get("events", {}).get(event_name, {})
    if "verbosity" in event_config:
        return event_config["verbosity"]

    # Fall back to default
    return config.get("logging", {}).get("verbosity", "summary")


def is_logging_enabled(event_name: str) -> bool:
    """
    Check if logging is enabled for this event.

    Args:
        event_name: Event name (lowercase)

    Returns:
        True if logging is enabled, False otherwise
    """
    # Validate event name (warn but don't block for forward-compatibility)
    if event_name not in VALID_EVENTS:
        print(f"WARNING: Unknown event '{event_name}', logging anyway", file=sys.stderr)

    config = load_config()

    # Check master enable from config (env vars already applied)
    if not config.get("logging", {}).get("enabled", True):
        return False

    # Check per-event enable (via env var only, for backward compatibility)
    event_env_key = f"CLAUDE_HOOK_LOG_{event_name.upper()}_ENABLED"
    event_enabled = os.environ.get(event_env_key, "").lower()
    if event_enabled in ("0", "false"):
        return False

    return True


# =============================================================================
# Entry Formatting
# =============================================================================


def format_minimal_entry(event_name: str, stdin_data: dict, duration_ms: int) -> dict:
    """
    Format a minimal log entry (~200 bytes).

    Fields: ts, event, session_id, tool (if present), exit, ms
    """
    entry = {
        "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "event": event_name,
        "session_id": stdin_data.get("session_id", ""),
        "exit": 0,
        "ms": duration_ms
    }

    # Add tool name if present (for tool events)
    if "tool_name" in stdin_data:
        entry["tool"] = stdin_data["tool_name"]

    # Add agent_id if present (for subagent events)
    if "agent_id" in stdin_data:
        entry["agent_id"] = stdin_data["agent_id"]

    return entry


def format_summary_entry(event_name: str, stdin_data: dict, duration_ms: int,
                         config: dict) -> dict:
    """
    Format a summary log entry (~500 bytes).

    Adds: transcript, tool_use_id, agent_transcript, perm_mode, workflow_id
    """
    entry = format_minimal_entry(event_name, stdin_data, duration_ms)

    # Add transcript reference
    if "transcript_path" in stdin_data:
        entry["transcript"] = stdin_data["transcript_path"]

    # Add tool_use_id for correlation
    if "tool_use_id" in stdin_data:
        entry["tool_use_id"] = stdin_data["tool_use_id"]

    # Add agent transcript path if present
    if "agent_transcript_path" in stdin_data:
        entry["agent_transcript"] = stdin_data["agent_transcript_path"]

    # Add permission mode if present
    if "permission_mode" in stdin_data:
        entry["perm_mode"] = stdin_data["permission_mode"]

    # Add cwd if present
    if "cwd" in stdin_data:
        entry["cwd"] = stdin_data["cwd"]

    return entry


def format_full_entry(event_name: str, stdin_data: dict, duration_ms: int,
                      config: dict) -> dict:
    """
    Format a full log entry (1-50KB).

    Includes complete stdin payload (current/legacy behavior).
    """
    return {
        "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "event": event_name,
        "stdin": stdin_data,
        "stdout": "",
        "exit_code": 0,
        "duration_ms": duration_ms
    }


def format_entry(event_name: str, stdin_data: dict, duration_ms: int,
                 config: dict) -> dict:
    """
    Format log entry based on configured verbosity.

    Args:
        event_name: Event name (lowercase)
        stdin_data: Parsed JSON input from hook
        duration_ms: Duration in milliseconds
        config: Configuration dictionary

    Returns:
        Formatted log entry dictionary
    """
    verbosity = get_verbosity(event_name, config)

    if verbosity == "minimal":
        return format_minimal_entry(event_name, stdin_data, duration_ms)
    elif verbosity == "summary":
        return format_summary_entry(event_name, stdin_data, duration_ms, config)
    else:  # full
        return format_full_entry(event_name, stdin_data, duration_ms, config)


# =============================================================================
# Log File Management
# =============================================================================


def get_log_file_path(event_name: str, config: dict) -> Path:
    """
    Get the log file path for today's logs, with rotation support.

    Args:
        event_name: Event name (lowercase)
        config: Configuration dictionary

    Returns:
        Path to log file (may be rotated: 2025-12-05.jsonl or 2025-12-05-001.jsonl)
    """
    log_dir = get_log_dir()
    event_dir = log_dir / event_name

    # Ensure log directory exists
    event_dir.mkdir(parents=True, exist_ok=True)

    # Get today's date in UTC
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    base_path = event_dir / f"{today}.jsonl"

    # Check if rotation is enabled
    rotation_config = config.get("logging", {}).get("rotation", {})
    if not rotation_config.get("enabled", True):
        return base_path

    max_size_bytes = rotation_config.get("max_file_size_mb", 10) * 1024 * 1024

    # If base file doesn't exist or is under size limit, use it
    if not base_path.exists():
        return base_path

    try:
        if base_path.stat().st_size < max_size_bytes:
            return base_path
    except OSError:
        return base_path

    # Find next available chunk
    chunk = 1
    while chunk <= 999:
        chunk_path = event_dir / f"{today}-{chunk:03d}.jsonl"
        if not chunk_path.exists():
            return chunk_path
        try:
            if chunk_path.stat().st_size < max_size_bytes:
                return chunk_path
        except OSError:
            return chunk_path
        chunk += 1

    # Safety fallback
    return event_dir / f"{today}-999.jsonl"


# =============================================================================
# Core Logging
# =============================================================================


def log_event(event_name: str, stdin_data: dict[str, Any]) -> None:
    """
    Log a hook event to daily JSONL file.

    Args:
        event_name: Event name (lowercase, e.g., "pretooluse")
        stdin_data: Parsed JSON input from hook

    Raises:
        ValueError: If event_name is empty or not lowercase
    """
    if not event_name:
        raise ValueError("Event name cannot be empty")
    if not event_name.islower():
        raise ValueError(f"Event name must be lowercase: {event_name}")

    config = load_config()

    # Record start time for duration calculation
    start_time = datetime.now(timezone.utc)

    # Calculate duration (minimal - just formatting overhead)
    end_time = datetime.now(timezone.utc)
    duration_ms = int((end_time - start_time).total_seconds() * 1000)

    # Format entry based on verbosity
    entry = format_entry(event_name, stdin_data, duration_ms, config)

    # Get log file path (with rotation support)
    log_path = get_log_file_path(event_name, config)

    # Serialize with compact JSON
    log_line = json.dumps(entry, separators=(",", ":"))

    # Append to log file (atomic for entries <4KB)
    try:
        with _WRITE_LOCK:
            with log_path.open("a", encoding="utf-8") as f:
                f.write(log_line + "\n")
    except OSError as e:
        # Log to stderr but don't fail (logging is non-critical)
        print(f"WARNING: Failed to write log: {e}", file=sys.stderr)


# =============================================================================
# Main Entry Point
# =============================================================================


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
