# Claude Code Observability Plugin - Enhanced Logging Implementation Spec

## Overview

This specification details enhancements to the `claude-code-observability` plugin to add configurable verbosity levels, size-based log rotation, and on-demand retention cleanup.

## Background & Rationale

### Current Architecture

The plugin logs all 10 Claude Code hook events to daily JSONL files:

```
hooks/log-hook-events/logs/
├── pretooluse/2025-12-05.jsonl
├── posttooluse/2025-12-05.jsonl
├── sessionstart/2025-12-05.jsonl
├── sessionend/2025-12-05.jsonl
├── userpromptsubmit/2025-12-05.jsonl
├── notification/2025-12-05.jsonl
├── permissionrequest/2025-12-05.jsonl
├── stop/2025-12-05.jsonl
├── subagentstop/2025-12-05.jsonl
└── precompact/2025-12-05.jsonl
```

**Current entry format (full payload):**
```json
{
  "timestamp": "2025-12-05T14:46:05.353103Z",
  "event": "pretooluse",
  "stdin": {
    "session_id": "5a5b8217-2e8b-40aa-8eb9-96b993603515",
    "transcript_path": "C:\\Users\\...\\5a5b8217.jsonl",
    "cwd": "C:\\Dev\\GitHub\\SETWorks\\SW2030",
    "permission_mode": "plan",
    "hook_event_name": "PreToolUse",
    "tool_name": "Bash",
    "tool_input": {
      "command": "ls -la ...",
      "description": "List directory contents"
    },
    "tool_use_id": "toolu_01YLvpepDvFYqiUbqPSSj9Jp"
  },
  "stdout": "",
  "exit_code": 0,
  "duration_ms": 0
}
```

### Problem

1. **Full payloads are 100% redundant** - Claude Code transcript files (`{session-id}.jsonl`) already capture complete tool input/output
2. **No size limits** - Files can grow unbounded (PostToolUse entries can be 50KB+ each with full file contents)
3. **No cleanup mechanism** - Old logs accumulate indefinitely
4. **Limited configuration** - Only master enable/disable via env var

### Solution

1. **Configurable verbosity** - `minimal`, `summary`, `full` levels
2. **Size-based rotation** - Split files at configurable threshold
3. **On-demand cleanup** - Slash command for retention management
4. **YAML configuration** - With env var override support

---

## File Changes

### File 1: NEW - `hooks/log-hook-events/config.yaml`

**Full file contents:**

```yaml
# Claude Code Observability Hook Logging Configuration
#
# This file controls how hook events are logged.
# All settings can be overridden via environment variables.
#
# Environment variable format: CLAUDE_HOOK_LOG_<SETTING>
# Example: CLAUDE_HOOK_LOG_VERBOSITY=full

logging:
  # Master enable/disable
  # Env override: CLAUDE_HOOK_LOG_EVENTS_ENABLED=true|false
  enabled: true

  # Verbosity level (minimal | summary | full)
  #
  # minimal (~200 bytes/entry):
  #   - timestamp, session_id, event, tool_name, exit_code, duration
  #   - Use for: audit trails, metrics, low-overhead monitoring
  #
  # summary (~500 bytes/entry) [DEFAULT]:
  #   - All minimal fields + transcript_path, tool_use_id
  #   - References transcripts instead of duplicating content
  #   - Use for: debugging, correlation, troubleshooting
  #
  # full (1-50KB/entry):
  #   - Complete stdin payload (current behavior)
  #   - 100% redundant with transcript files
  #   - Use for: deep debugging when transcripts unavailable
  #
  # Env override: CLAUDE_HOOK_LOG_VERBOSITY=minimal|summary|full
  verbosity: summary

  # Size-based log file rotation
  rotation:
    # Enable/disable rotation
    # Env override: CLAUDE_HOOK_LOG_ROTATION_ENABLED=true|false
    enabled: true

    # Maximum file size in MB before rotating
    # When exceeded, creates: 2025-12-05-001.jsonl, 2025-12-05-002.jsonl, etc.
    # Env override: CLAUDE_HOOK_LOG_ROTATION_MAX_SIZE_MB=10
    max_file_size_mb: 10

  # Retention settings (used by cleanup command only, not automatic)
  retention:
    # Default max age for cleanup command
    # Env override: CLAUDE_HOOK_LOG_RETENTION_MAX_AGE_DAYS=30
    max_age_days: 30

  # Per-event verbosity overrides
  # Use to set different verbosity for specific events
  # Env override: CLAUDE_HOOK_LOG_EVENT_<EVENT>_VERBOSITY=minimal|summary|full
  events:
    # PostToolUse has largest payloads (includes full tool responses)
    # Setting to minimal saves the most space
    posttooluse:
      verbosity: minimal

    # SessionStart is small, keep full for debugging
    sessionstart:
      verbosity: full

    # UserPromptSubmit can have large prompts
    userpromptsubmit:
      verbosity: summary

    # All other events use the default verbosity above
    # Uncomment to override:
    # pretooluse:
    #   verbosity: summary
    # sessionend:
    #   verbosity: full
    # notification:
    #   verbosity: minimal
    # permissionrequest:
    #   verbosity: summary
    # stop:
    #   verbosity: summary
    # subagentstop:
    #   verbosity: summary
    # precompact:
    #   verbosity: full

# Optional: Workflow correlation ID
# Set via env var to correlate events across multiple sessions
# Useful for tracking multi-session workflows
# Env: CLAUDE_WORKFLOW_ID=my-feature-branch-work
correlation:
  workflow_id: null
```

---

### File 2: MODIFY - `hooks/log-hook-events/python/log_event.py`

**Current file location:** `hooks/log-hook-events/python/log_event.py`

**Changes required:**

#### 2.1 Add imports at top of file

```python
# Add these imports after existing imports
import yaml
from typing import Optional, Any
```

#### 2.2 Add configuration loading functions

**Add after the existing imports and before `get_log_dir()`:**

```python
# Configuration cache (loaded once per invocation)
_config_cache: Optional[dict] = None

def get_config_path() -> Path:
    """Get path to config.yaml file."""
    # Config is in the same directory as the logs
    return get_log_dir().parent / "config.yaml"

def load_config() -> dict:
    """Load configuration from YAML file with environment variable overrides."""
    global _config_cache

    if _config_cache is not None:
        return _config_cache

    # Default configuration
    config = {
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
        },
        "correlation": {
            "workflow_id": None
        }
    }

    # Load from YAML file if exists
    config_path = get_config_path()
    if config_path.exists():
        try:
            with open(config_path, 'r', encoding='utf-8') as f:
                yaml_config = yaml.safe_load(f)
                if yaml_config:
                    # Deep merge yaml_config into config
                    _deep_merge(config, yaml_config)
        except Exception as e:
            print(f"Warning: Failed to load config.yaml: {e}", file=sys.stderr)

    # Apply environment variable overrides
    _apply_env_overrides(config)

    _config_cache = config
    return config

def _deep_merge(base: dict, override: dict) -> None:
    """Deep merge override dict into base dict."""
    for key, value in override.items():
        if key in base and isinstance(base[key], dict) and isinstance(value, dict):
            _deep_merge(base[key], value)
        else:
            base[key] = value

def _apply_env_overrides(config: dict) -> None:
    """Apply environment variable overrides to config."""
    env_mappings = [
        ("CLAUDE_HOOK_LOG_EVENTS_ENABLED", ["logging", "enabled"], lambda x: x.lower() in ("1", "true")),
        ("CLAUDE_HOOK_LOG_VERBOSITY", ["logging", "verbosity"], str),
        ("CLAUDE_HOOK_LOG_ROTATION_ENABLED", ["logging", "rotation", "enabled"], lambda x: x.lower() in ("1", "true")),
        ("CLAUDE_HOOK_LOG_ROTATION_MAX_SIZE_MB", ["logging", "rotation", "max_file_size_mb"], int),
        ("CLAUDE_HOOK_LOG_RETENTION_MAX_AGE_DAYS", ["logging", "retention", "max_age_days"], int),
        ("CLAUDE_WORKFLOW_ID", ["correlation", "workflow_id"], str),
    ]

    for env_key, path, converter in env_mappings:
        env_value = os.environ.get(env_key)
        if env_value is not None:
            try:
                _set_nested(config, path, converter(env_value))
            except (ValueError, TypeError) as e:
                print(f"Warning: Invalid value for {env_key}: {e}", file=sys.stderr)

    # Per-event verbosity overrides
    for event in ["pretooluse", "posttooluse", "sessionstart", "sessionend",
                  "userpromptsubmit", "notification", "permissionrequest",
                  "stop", "subagentstop", "precompact"]:
        env_key = f"CLAUDE_HOOK_LOG_EVENT_{event.upper()}_VERBOSITY"
        env_value = os.environ.get(env_key)
        if env_value is not None:
            if "events" not in config["logging"]:
                config["logging"]["events"] = {}
            if event not in config["logging"]["events"]:
                config["logging"]["events"][event] = {}
            config["logging"]["events"][event]["verbosity"] = env_value

def _set_nested(d: dict, path: list, value: Any) -> None:
    """Set a value in a nested dict using a path list."""
    for key in path[:-1]:
        d = d.setdefault(key, {})
    d[path[-1]] = value

def get_verbosity(event_name: str, config: dict) -> str:
    """Get verbosity level for a specific event."""
    # Check per-event override first
    event_config = config.get("logging", {}).get("events", {}).get(event_name.lower(), {})
    if "verbosity" in event_config:
        return event_config["verbosity"]

    # Fall back to default
    return config.get("logging", {}).get("verbosity", "summary")
```

#### 2.3 Add entry formatting functions

**Add after the config functions:**

```python
def format_minimal_entry(event_name: str, stdin_data: dict, duration_ms: int) -> dict:
    """Format a minimal log entry (~200 bytes)."""
    entry = {
        "ts": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "event": event_name.lower(),
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

def format_summary_entry(event_name: str, stdin_data: dict, duration_ms: int, config: dict) -> dict:
    """Format a summary log entry (~500 bytes)."""
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

    # Add workflow_id if configured
    workflow_id = config.get("correlation", {}).get("workflow_id")
    if workflow_id:
        entry["workflow_id"] = workflow_id

    return entry

def format_full_entry(event_name: str, stdin_data: dict, duration_ms: int, config: dict) -> dict:
    """Format a full log entry (current behavior, 1-50KB)."""
    entry = {
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "event": event_name.lower(),
        "stdin": stdin_data,
        "stdout": "",
        "exit_code": 0,
        "duration_ms": duration_ms
    }

    # Add workflow_id if configured
    workflow_id = config.get("correlation", {}).get("workflow_id")
    if workflow_id:
        entry["workflow_id"] = workflow_id

    return entry

def format_entry(event_name: str, stdin_data: dict, duration_ms: int, config: dict) -> dict:
    """Format log entry based on configured verbosity."""
    verbosity = get_verbosity(event_name, config)

    if verbosity == "minimal":
        return format_minimal_entry(event_name, stdin_data, duration_ms)
    elif verbosity == "summary":
        return format_summary_entry(event_name, stdin_data, duration_ms, config)
    else:  # full
        return format_full_entry(event_name, stdin_data, duration_ms, config)
```

#### 2.4 Modify `get_log_file_path()` for rotation

**Replace the existing `get_log_file_path()` function with:**

```python
def get_log_file_path(event_name: str, config: dict) -> Path:
    """
    Get the path to the log file for an event.
    Implements size-based rotation if enabled.
    """
    log_dir = get_log_dir()
    event_dir = log_dir / event_name.lower()
    event_dir.mkdir(parents=True, exist_ok=True)

    today = datetime.utcnow().strftime("%Y-%m-%d")
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
    while True:
        chunk_path = event_dir / f"{today}-{chunk:03d}.jsonl"
        if not chunk_path.exists():
            return chunk_path
        try:
            if chunk_path.stat().st_size < max_size_bytes:
                return chunk_path
        except OSError:
            return chunk_path
        chunk += 1

        # Safety limit to prevent infinite loop
        if chunk > 999:
            return chunk_path
```

#### 2.5 Modify `is_logging_enabled()` to use config

**Replace the existing `is_logging_enabled()` function with:**

```python
def is_logging_enabled(event_name: str) -> bool:
    """
    Check if logging is enabled for this event.
    Checks both config file and environment variables.
    """
    config = load_config()

    # Check master enable from config (env vars already applied)
    if not config.get("logging", {}).get("enabled", True):
        return False

    # Check per-event enable (via env var only, for backward compatibility)
    event_env_key = f"CLAUDE_HOOK_LOG_{event_name.upper()}_ENABLED"
    event_enabled = os.environ.get(event_env_key, "").lower()
    if event_enabled == "false" or event_enabled == "0":
        return False

    return True
```

#### 2.6 Modify `log_event()` to use new formatting

**Replace the existing `log_event()` function with:**

```python
def log_event(event_name: str, stdin_data: dict) -> None:
    """
    Log an event to the appropriate JSONL file.

    Args:
        event_name: The type of event (e.g., 'pretooluse', 'posttooluse')
        stdin_data: The JSON data received from stdin
    """
    start_time = datetime.utcnow()
    config = load_config()

    try:
        # Format entry based on verbosity
        duration_ms = 0  # Will be updated if we measure
        entry = format_entry(event_name, stdin_data, duration_ms, config)

        # Get log file path (with rotation support)
        log_path = get_log_file_path(event_name, config)

        # Write entry
        with _file_lock:
            with open(log_path, 'a', encoding='utf-8') as f:
                f.write(json.dumps(entry, separators=(',', ':')) + '\n')

    except Exception as e:
        # Never fail the hook - just log to stderr
        print(f"Error logging {event_name}: {e}", file=sys.stderr)
```

#### 2.7 Full modified `log_event.py`

For reference, here's the complete structure of the modified file:

```python
#!/usr/bin/env python3
"""
Claude Code Hook Event Logger

Logs hook events to JSONL files with configurable verbosity and rotation.
"""

import json
import os
import sys
import threading
import yaml
from datetime import datetime
from pathlib import Path
from typing import Optional, Any

# Thread lock for file operations
_file_lock = threading.Lock()

# Configuration cache
_config_cache: Optional[dict] = None

# ============================================================================
# Path Resolution
# ============================================================================

def get_log_dir() -> Path:
    """Get the directory where log files are stored."""
    # Try environment variable first
    plugin_root = os.environ.get("CLAUDE_PLUGIN_ROOT")
    if plugin_root:
        return Path(plugin_root) / "hooks" / "log-hook-events" / "logs"

    # Fall back to relative path from this script
    return Path(__file__).parent.parent / "logs"

def get_config_path() -> Path:
    """Get path to config.yaml file."""
    return get_log_dir().parent / "config.yaml"

# ============================================================================
# Configuration
# ============================================================================

def load_config() -> dict:
    """Load configuration from YAML file with environment variable overrides."""
    global _config_cache

    if _config_cache is not None:
        return _config_cache

    # Default configuration
    config = {
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
        },
        "correlation": {
            "workflow_id": None
        }
    }

    # Load from YAML file if exists
    config_path = get_config_path()
    if config_path.exists():
        try:
            with open(config_path, 'r', encoding='utf-8') as f:
                yaml_config = yaml.safe_load(f)
                if yaml_config:
                    _deep_merge(config, yaml_config)
        except Exception as e:
            print(f"Warning: Failed to load config.yaml: {e}", file=sys.stderr)

    # Apply environment variable overrides
    _apply_env_overrides(config)

    _config_cache = config
    return config

def _deep_merge(base: dict, override: dict) -> None:
    """Deep merge override dict into base dict."""
    for key, value in override.items():
        if key in base and isinstance(base[key], dict) and isinstance(value, dict):
            _deep_merge(base[key], value)
        else:
            base[key] = value

def _apply_env_overrides(config: dict) -> None:
    """Apply environment variable overrides to config."""
    env_mappings = [
        ("CLAUDE_HOOK_LOG_EVENTS_ENABLED", ["logging", "enabled"], lambda x: x.lower() in ("1", "true")),
        ("CLAUDE_HOOK_LOG_VERBOSITY", ["logging", "verbosity"], str),
        ("CLAUDE_HOOK_LOG_ROTATION_ENABLED", ["logging", "rotation", "enabled"], lambda x: x.lower() in ("1", "true")),
        ("CLAUDE_HOOK_LOG_ROTATION_MAX_SIZE_MB", ["logging", "rotation", "max_file_size_mb"], int),
        ("CLAUDE_HOOK_LOG_RETENTION_MAX_AGE_DAYS", ["logging", "retention", "max_age_days"], int),
        ("CLAUDE_WORKFLOW_ID", ["correlation", "workflow_id"], str),
    ]

    for env_key, path, converter in env_mappings:
        env_value = os.environ.get(env_key)
        if env_value is not None:
            try:
                _set_nested(config, path, converter(env_value))
            except (ValueError, TypeError) as e:
                print(f"Warning: Invalid value for {env_key}: {e}", file=sys.stderr)

    # Per-event verbosity overrides
    for event in ["pretooluse", "posttooluse", "sessionstart", "sessionend",
                  "userpromptsubmit", "notification", "permissionrequest",
                  "stop", "subagentstop", "precompact"]:
        env_key = f"CLAUDE_HOOK_LOG_EVENT_{event.upper()}_VERBOSITY"
        env_value = os.environ.get(env_key)
        if env_value is not None:
            if "events" not in config["logging"]:
                config["logging"]["events"] = {}
            if event not in config["logging"]["events"]:
                config["logging"]["events"][event] = {}
            config["logging"]["events"][event]["verbosity"] = env_value

def _set_nested(d: dict, path: list, value: Any) -> None:
    """Set a value in a nested dict using a path list."""
    for key in path[:-1]:
        d = d.setdefault(key, {})
    d[path[-1]] = value

def get_verbosity(event_name: str, config: dict) -> str:
    """Get verbosity level for a specific event."""
    event_config = config.get("logging", {}).get("events", {}).get(event_name.lower(), {})
    if "verbosity" in event_config:
        return event_config["verbosity"]
    return config.get("logging", {}).get("verbosity", "summary")

def is_logging_enabled(event_name: str) -> bool:
    """Check if logging is enabled for this event."""
    config = load_config()

    if not config.get("logging", {}).get("enabled", True):
        return False

    event_env_key = f"CLAUDE_HOOK_LOG_{event_name.upper()}_ENABLED"
    event_enabled = os.environ.get(event_env_key, "").lower()
    if event_enabled == "false" or event_enabled == "0":
        return False

    return True

# ============================================================================
# Entry Formatting
# ============================================================================

def format_minimal_entry(event_name: str, stdin_data: dict, duration_ms: int) -> dict:
    """Format a minimal log entry (~200 bytes)."""
    entry = {
        "ts": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "event": event_name.lower(),
        "session_id": stdin_data.get("session_id", ""),
        "exit": 0,
        "ms": duration_ms
    }

    if "tool_name" in stdin_data:
        entry["tool"] = stdin_data["tool_name"]
    if "agent_id" in stdin_data:
        entry["agent_id"] = stdin_data["agent_id"]

    return entry

def format_summary_entry(event_name: str, stdin_data: dict, duration_ms: int, config: dict) -> dict:
    """Format a summary log entry (~500 bytes)."""
    entry = format_minimal_entry(event_name, stdin_data, duration_ms)

    if "transcript_path" in stdin_data:
        entry["transcript"] = stdin_data["transcript_path"]
    if "tool_use_id" in stdin_data:
        entry["tool_use_id"] = stdin_data["tool_use_id"]
    if "agent_transcript_path" in stdin_data:
        entry["agent_transcript"] = stdin_data["agent_transcript_path"]
    if "permission_mode" in stdin_data:
        entry["perm_mode"] = stdin_data["permission_mode"]

    workflow_id = config.get("correlation", {}).get("workflow_id")
    if workflow_id:
        entry["workflow_id"] = workflow_id

    return entry

def format_full_entry(event_name: str, stdin_data: dict, duration_ms: int, config: dict) -> dict:
    """Format a full log entry (1-50KB)."""
    entry = {
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "event": event_name.lower(),
        "stdin": stdin_data,
        "stdout": "",
        "exit_code": 0,
        "duration_ms": duration_ms
    }

    workflow_id = config.get("correlation", {}).get("workflow_id")
    if workflow_id:
        entry["workflow_id"] = workflow_id

    return entry

def format_entry(event_name: str, stdin_data: dict, duration_ms: int, config: dict) -> dict:
    """Format log entry based on configured verbosity."""
    verbosity = get_verbosity(event_name, config)

    if verbosity == "minimal":
        return format_minimal_entry(event_name, stdin_data, duration_ms)
    elif verbosity == "summary":
        return format_summary_entry(event_name, stdin_data, duration_ms, config)
    else:
        return format_full_entry(event_name, stdin_data, duration_ms, config)

# ============================================================================
# Log File Management
# ============================================================================

def get_log_file_path(event_name: str, config: dict) -> Path:
    """Get the path to the log file, with rotation support."""
    log_dir = get_log_dir()
    event_dir = log_dir / event_name.lower()
    event_dir.mkdir(parents=True, exist_ok=True)

    today = datetime.utcnow().strftime("%Y-%m-%d")
    base_path = event_dir / f"{today}.jsonl"

    rotation_config = config.get("logging", {}).get("rotation", {})
    if not rotation_config.get("enabled", True):
        return base_path

    max_size_bytes = rotation_config.get("max_file_size_mb", 10) * 1024 * 1024

    if not base_path.exists():
        return base_path

    try:
        if base_path.stat().st_size < max_size_bytes:
            return base_path
    except OSError:
        return base_path

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

    return event_dir / f"{today}-999.jsonl"

# ============================================================================
# Core Logging
# ============================================================================

def log_event(event_name: str, stdin_data: dict) -> None:
    """Log an event to the appropriate JSONL file."""
    config = load_config()

    try:
        entry = format_entry(event_name, stdin_data, 0, config)
        log_path = get_log_file_path(event_name, config)

        with _file_lock:
            with open(log_path, 'a', encoding='utf-8') as f:
                f.write(json.dumps(entry, separators=(',', ':')) + '\n')
    except Exception as e:
        print(f"Error logging {event_name}: {e}", file=sys.stderr)

# ============================================================================
# Main Entry Point
# ============================================================================

def main():
    """Main entry point for the hook logger."""
    if len(sys.argv) < 2:
        print("Usage: log_event.py <event_name>", file=sys.stderr)
        sys.exit(1)

    event_name = sys.argv[1]

    if not is_logging_enabled(event_name):
        sys.exit(0)

    try:
        stdin_data = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f"Error parsing stdin JSON: {e}", file=sys.stderr)
        sys.exit(0)

    log_event(event_name, stdin_data)
    sys.exit(0)

if __name__ == "__main__":
    main()
```

---

### File 3: NEW - `hooks/log-hook-events/python/cleanup_logs.py`

**Full file contents:**

```python
#!/usr/bin/env python3
"""
Claude Code Hook Log Cleanup Utility

Cleans up old log files based on retention policy.
"""

import argparse
import json
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path
from typing import List, Tuple


def get_log_dir() -> Path:
    """Get the directory where log files are stored."""
    plugin_root = os.environ.get("CLAUDE_PLUGIN_ROOT")
    if plugin_root:
        return Path(plugin_root) / "hooks" / "log-hook-events" / "logs"
    return Path(__file__).parent.parent / "logs"


def parse_log_date(filename: str) -> datetime:
    """
    Parse date from log filename.

    Supports formats:
    - 2025-12-05.jsonl
    - 2025-12-05-001.jsonl (rotated)
    """
    stem = Path(filename).stem
    parts = stem.split("-")

    if len(parts) >= 3:
        date_str = f"{parts[0]}-{parts[1]}-{parts[2]}"
        return datetime.strptime(date_str, "%Y-%m-%d")

    raise ValueError(f"Cannot parse date from filename: {filename}")


def find_old_logs(max_age_days: int) -> List[Tuple[Path, datetime]]:
    """
    Find all log files older than max_age_days.

    Returns list of (path, file_date) tuples.
    """
    log_dir = get_log_dir()
    cutoff = datetime.now() - timedelta(days=max_age_days)
    old_files = []

    if not log_dir.exists():
        return old_files

    for event_dir in log_dir.iterdir():
        if not event_dir.is_dir():
            continue

        for log_file in event_dir.glob("*.jsonl"):
            try:
                file_date = parse_log_date(log_file.name)
                if file_date < cutoff:
                    old_files.append((log_file, file_date))
            except ValueError:
                # Skip files that don't match expected format
                continue

    return sorted(old_files, key=lambda x: x[1])


def calculate_size(files: List[Tuple[Path, datetime]]) -> int:
    """Calculate total size of files in bytes."""
    total = 0
    for path, _ in files:
        try:
            total += path.stat().st_size
        except OSError:
            continue
    return total


def format_size(size_bytes: int) -> str:
    """Format size in human-readable form."""
    if size_bytes < 1024:
        return f"{size_bytes} B"
    elif size_bytes < 1024 * 1024:
        return f"{size_bytes / 1024:.1f} KB"
    else:
        return f"{size_bytes / (1024 * 1024):.1f} MB"


def cleanup_logs(max_age_days: int, dry_run: bool = False, verbose: bool = False) -> dict:
    """
    Delete log files older than max_age_days.

    Args:
        max_age_days: Delete files older than this many days
        dry_run: If True, don't actually delete files
        verbose: If True, print each file being deleted

    Returns:
        dict with cleanup results
    """
    old_files = find_old_logs(max_age_days)

    if not old_files:
        return {
            "deleted_count": 0,
            "deleted_size": 0,
            "deleted_files": [],
            "dry_run": dry_run
        }

    total_size = calculate_size(old_files)
    deleted_files = []

    for path, file_date in old_files:
        if verbose:
            action = "Would delete" if dry_run else "Deleting"
            print(f"{action}: {path} ({file_date.strftime('%Y-%m-%d')})")

        if not dry_run:
            try:
                path.unlink()
                deleted_files.append(str(path))
            except OSError as e:
                print(f"Error deleting {path}: {e}", file=sys.stderr)
        else:
            deleted_files.append(str(path))

    # Clean up empty directories
    if not dry_run:
        log_dir = get_log_dir()
        for event_dir in log_dir.iterdir():
            if event_dir.is_dir() and not any(event_dir.iterdir()):
                try:
                    event_dir.rmdir()
                except OSError:
                    pass

    return {
        "deleted_count": len(deleted_files),
        "deleted_size": total_size,
        "deleted_size_formatted": format_size(total_size),
        "deleted_files": deleted_files,
        "dry_run": dry_run
    }


def main():
    parser = argparse.ArgumentParser(
        description="Clean up old Claude Code hook log files"
    )
    parser.add_argument(
        "--days", "-d",
        type=int,
        default=30,
        help="Delete logs older than this many days (default: 30)"
    )
    parser.add_argument(
        "--dry-run", "-n",
        action="store_true",
        help="Show what would be deleted without actually deleting"
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Print each file being deleted"
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output results as JSON"
    )

    args = parser.parse_args()

    result = cleanup_logs(
        max_age_days=args.days,
        dry_run=args.dry_run,
        verbose=args.verbose
    )

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        if result["deleted_count"] == 0:
            print(f"No log files older than {args.days} days found.")
        else:
            action = "Would delete" if args.dry_run else "Deleted"
            print(f"{action} {result['deleted_count']} files ({result['deleted_size_formatted']})")

    sys.exit(0)


if __name__ == "__main__":
    main()
```

---

### File 4: NEW - Slash Command `cleanup-hook-logs.md`

**Location:** `~/.claude/plugins/marketplaces/claude-code-plugins/plugins/claude-code-observability/commands/cleanup-hook-logs.md`

**Note:** The plugin needs a `commands/` directory. Create it if it doesn't exist.

**Full file contents:**

```markdown
---
description: Clean up old Claude Code hook log files based on retention policy
arguments:
  - name: days
    description: Delete logs older than N days (default: 30, from config)
    required: false
  - name: dry-run
    description: Show what would be deleted without actually deleting
    required: false
---

# Cleanup Hook Logs

Delete old hook log files to free up disk space.

## Usage Examples

```bash
# Delete logs older than 30 days (default)
/cleanup-hook-logs

# Delete logs older than 7 days
/cleanup-hook-logs 7

# Preview what would be deleted (dry run)
/cleanup-hook-logs --dry-run

# Delete logs older than 14 days with verbose output
/cleanup-hook-logs 14 --verbose
```

## Execution

Run the cleanup script with the provided arguments:

```bash
python "${CLAUDE_PLUGIN_ROOT}/hooks/log-hook-events/python/cleanup_logs.py" --days ${1:-30} ${2:+$2} --verbose
```

## What Gets Deleted

- All `.jsonl` files in the logs directory older than the specified days
- Both base files (`2025-12-05.jsonl`) and rotated files (`2025-12-05-001.jsonl`)
- Empty event directories are removed after cleanup

## Safety Notes

- Use `--dry-run` first to preview what will be deleted
- Deleted files cannot be recovered
- The cleanup respects the retention policy in `config.yaml` by default
```

---

## Correlation Strategy

### Within-Session Correlation (Already Supported)

The existing hook payloads include:

| Field | Description | Scope |
|-------|-------------|-------|
| `session_id` | Main session UUID | Persists through compactions |
| `transcript_path` | Path to main transcript | Updates if transcript rotates |
| `agent_id` | Subagent UUID | Subagent events only |
| `agent_transcript_path` | Path to agent transcript | Subagent events only |
| `tool_use_id` | Tool invocation UUID | Tool events only |

**Query patterns:**

```bash
# Find all events for a session
grep "session_id.*5a5b8217" logs/*/2025-12-05*.jsonl

# Find subagent events for a session
grep "session_id.*5a5b8217" logs/subagentstop/*.jsonl

# Correlate tool use across events
grep "toolu_01YLvp" logs/*/2025-12-05*.jsonl
```

### Cross-Session Correlation (New Feature)

For multi-session workflows, set the `CLAUDE_WORKFLOW_ID` environment variable:

```bash
# In PowerShell
$env:CLAUDE_WORKFLOW_ID = "feature-xyz-implementation"

# In Bash
export CLAUDE_WORKFLOW_ID="feature-xyz-implementation"
```

Then query across sessions:

```bash
grep "workflow_id.*feature-xyz" logs/*/2025-12-*.jsonl
```

---

## Testing Checklist

### 1. Configuration Loading

```bash
# Test default config (no config.yaml)
rm -f ~/.claude/plugins/.../hooks/log-hook-events/config.yaml
# Trigger any tool use
# Check logs - should use summary format

# Test config.yaml loading
cp config.yaml ~/.claude/plugins/.../hooks/log-hook-events/
# Trigger tool use
# Check logs - should use configured format

# Test env var override
export CLAUDE_HOOK_LOG_VERBOSITY=full
# Trigger tool use
# Check logs - should use full format despite config.yaml
```

### 2. Verbosity Levels

```bash
# Set each level and verify output format
export CLAUDE_HOOK_LOG_VERBOSITY=minimal
# Trigger Read tool
cat logs/pretooluse/$(date +%Y-%m-%d).jsonl | tail -1
# Should see ~200 byte entry with: ts, event, session_id, tool, exit, ms

export CLAUDE_HOOK_LOG_VERBOSITY=summary
# Trigger Read tool
cat logs/pretooluse/$(date +%Y-%m-%d).jsonl | tail -1
# Should see ~500 byte entry with: + transcript, tool_use_id

export CLAUDE_HOOK_LOG_VERBOSITY=full
# Trigger Read tool
cat logs/pretooluse/$(date +%Y-%m-%d).jsonl | tail -1
# Should see full stdin payload
```

### 3. Per-Event Override

```bash
# Set PostToolUse to minimal, default to full
export CLAUDE_HOOK_LOG_VERBOSITY=full
export CLAUDE_HOOK_LOG_EVENT_POSTTOOLUSE_VERBOSITY=minimal
# Trigger any tool
# Check pretooluse - should be full
# Check posttooluse - should be minimal
```

### 4. Size-Based Rotation

```bash
# Create a large log file
for i in {1..10000}; do
  echo '{"ts":"2025-12-05T12:00:00Z","event":"test","data":"'$(head -c 1000 /dev/urandom | base64)'"}'
done >> logs/pretooluse/2025-12-05.jsonl

# Check file size
ls -la logs/pretooluse/

# Trigger another tool use
# Check if rotation occurred
ls -la logs/pretooluse/
# Should see 2025-12-05-001.jsonl if size exceeded 10MB
```

### 5. Cleanup Command

```bash
# Dry run
python cleanup_logs.py --days 7 --dry-run --verbose

# Actual cleanup
python cleanup_logs.py --days 30 --verbose

# JSON output
python cleanup_logs.py --days 7 --json
```

### 6. Backward Compatibility

```bash
# Remove config.yaml
rm -f config.yaml

# Should still work with env var only
export CLAUDE_HOOK_LOG_EVENTS_ENABLED=true
# Trigger tool use
# Check logs - should work with default settings
```

---

## Migration Guide

### For Existing Users

1. **No action required** - Plugin continues to work with current env var approach
2. **Optional:** Add `config.yaml` to customize verbosity and rotation
3. **Recommended:** Set `verbosity: summary` to reduce log size by 90%+

### Configuration Migration

```yaml
# Minimal config to get started
logging:
  verbosity: summary  # Reduce from full to summary
  rotation:
    max_file_size_mb: 10  # Enable rotation at 10MB
```

### Environment Variable Compatibility

All existing env vars continue to work:
- `CLAUDE_HOOK_LOG_EVENTS_ENABLED` - Master toggle
- `CLAUDE_HOOK_LOG_<EVENT>_ENABLED` - Per-event toggle

New env vars added:
- `CLAUDE_HOOK_LOG_VERBOSITY` - Default verbosity level
- `CLAUDE_HOOK_LOG_EVENT_<EVENT>_VERBOSITY` - Per-event verbosity
- `CLAUDE_HOOK_LOG_ROTATION_ENABLED` - Enable/disable rotation
- `CLAUDE_HOOK_LOG_ROTATION_MAX_SIZE_MB` - Rotation threshold
- `CLAUDE_WORKFLOW_ID` - Cross-session correlation ID

---

## Estimated Impact

| Metric | Before | After (summary default) |
|--------|--------|-------------------------|
| Avg entry size | 5-50 KB | 500 bytes |
| Daily log size (heavy use) | 50-100 MB | 2-5 MB |
| Storage per month | 1.5-3 GB | 60-150 MB |
| Query performance | Slow (large files) | Fast (smaller files + rotation) |

---

## Files Summary

| File | Action | Location |
|------|--------|----------|
| `config.yaml` | CREATE | `hooks/log-hook-events/config.yaml` |
| `log_event.py` | MODIFY | `hooks/log-hook-events/python/log_event.py` |
| `cleanup_logs.py` | CREATE | `hooks/log-hook-events/python/cleanup_logs.py` |
| `cleanup-hook-logs.md` | CREATE | `commands/cleanup-hook-logs.md` |
