#!/usr/bin/env bash
# logging-utils.sh - Shared logging utilities for hook event logging
#
# Provides functions for logging hook events via Python.
# The Python logger (log_event.py) handles all JSONL file operations.
#
# Usage: Source this file in your hook script: source "$(dirname "$0")/logging-utils.sh"

set -euo pipefail

# Run the Python-based logger safely (never block hook execution)
# Usage: run_python_event_logger "pretooluse" "$SCRIPT_DIR"
run_python_event_logger() {
    local event_name="$1"
    local script_dir="$2"
    local python_bin="${PYTHON_BIN:-python3}"
    local logger_path="${script_dir}/../python/log_event.py"

    if ! command -v "$python_bin" &> /dev/null; then
        # Consume stdin so the pipeline doesn't hang, but don't block the hook
        cat >/dev/null
        echo "WARNING: ${event_name} logger skipped (missing ${python_bin})." >&2
        return 0
    fi

    if ! "$python_bin" "$logger_path" "$event_name"; then
        echo "WARNING: ${event_name} logger encountered an error (non-blocking)." >&2
    fi

    return 0
}
