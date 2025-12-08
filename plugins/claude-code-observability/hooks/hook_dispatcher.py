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
"""
import sys
import json
import os
from pathlib import Path
from datetime import datetime, timezone

# Minimum Python version check - exit silently on old versions
if sys.version_info < (3, 6):
    sys.exit(0)


def main():
    """Main entry point - always exits 0."""
    try:
        # Get event name from args
        event_name = sys.argv[1] if len(sys.argv) > 1 else "unknown"

        # Check if logging is enabled (opt-in via environment variable)
        master_enabled = os.environ.get("CLAUDE_HOOK_LOG_EVENTS_ENABLED", "0")
        if master_enabled not in ("1", "true", "True", "TRUE"):
            # Logging not enabled - consume stdin and exit silently
            if not sys.stdin.isatty():
                sys.stdin.read()
            sys.exit(0)

        # Check individual event toggle (allows disabling specific events)
        event_upper = event_name.upper().replace("-", "_")
        event_enabled = os.environ.get(f"CLAUDE_HOOK_LOG_{event_upper}_ENABLED", "1")
        if event_enabled in ("0", "false", "False", "FALSE"):
            if not sys.stdin.isatty():
                sys.stdin.read()
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

        # Determine log directory using pathlib (cross-platform)
        project_dir = os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd())
        log_dir = Path(project_dir) / ".claude" / "logs" / "hooks"
        log_dir.mkdir(parents=True, exist_ok=True)

        # Create log entry
        log_entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "event": event_name,
            "session_id": os.environ.get("CLAUDE_SESSION_ID", "unknown"),
            "input": hook_input,
        }

        # Add environment context if available
        env_context = {}
        for key in ("CLAUDE_PROJECT_DIR", "CLAUDE_PLUGIN_ROOT", "CLAUDE_MODEL"):
            if key in os.environ:
                env_context[key] = os.environ[key]
        if env_context:
            log_entry["environment"] = env_context

        # Append to daily JSONL file
        today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        log_file = log_dir / f"events-{today}.jsonl"

        with open(log_file, "a", encoding="utf-8") as f:
            f.write(json.dumps(log_entry, ensure_ascii=False, separators=(",", ":")) + "\n")

    except Exception as e:
        # Swallow ALL errors - never block Claude Code
        # But optionally log for debugging when troubleshooting hooks
        if os.environ.get("CLAUDE_HOOK_LOG_DEBUG", "0") in ("1", "true", "True", "TRUE"):
            print(f"Hook dispatcher error: {e}", file=sys.stderr)

    # Always exit 0
    sys.exit(0)


if __name__ == "__main__":
    main()
