#!/usr/bin/env bash
# config-utils.sh - Configuration utilities for Claude Code hooks
#
# Simplified version: Configuration is now inline in each hook script.
# This file provides only logging and utility functions.
#
# Per official Claude Code patterns, hooks are configured in settings.json only.
# Custom YAML configurations have been removed to align with official patterns.
#
# Usage: Source this file in your hook script: source "$(dirname "$0")/../shared/config-utils.sh"

set -euo pipefail

# Default log level (can be overridden via CLAUDE_HOOK_LOG_LEVEL env var)
HOOK_LOG_LEVEL="${CLAUDE_HOOK_LOG_LEVEL:-info}"

# Log message based on log level
# Usage: log_message "info" "This is a message"
# Levels: debug < info < warn < error
log_message() {
    local level="$1"
    local message="$2"
    local log_level="${HOOK_LOG_LEVEL:-info}"

    # Simple log level filtering (debug < info < warn < error)
    case "$log_level" in
        debug)
            ;;
        info)
            if [ "$level" = "debug" ]; then return; fi
            ;;
        warn)
            if [ "$level" = "debug" ] || [ "$level" = "info" ]; then return; fi
            ;;
        error)
            if [ "$level" != "error" ]; then return; fi
            ;;
    esac

    echo "[$(date -u +"%Y-%m-%d %H:%M:%S UTC")] [${level^^}] $message" >&2
}

# Check if hook is enabled via environment variable
# Usage: is_hook_enabled "HOOK_NAME" || exit 0
# Example: is_hook_enabled "BLOCK_ABSOLUTE_PATHS" || exit 0
# Set CLAUDE_HOOK_DISABLED_BLOCK_ABSOLUTE_PATHS=1 to disable
is_hook_enabled() {
    local hook_name="$1"
    local env_var="CLAUDE_HOOK_DISABLED_${hook_name}"

    # Check if explicitly disabled via environment variable
    if [ "${!env_var:-}" = "1" ] || [ "${!env_var:-}" = "true" ]; then
        return 1
    fi

    return 0
}

# Standard exit codes (per official Claude Code documentation)
# 0 = Allow/Success
# 1 = Warning (non-blocking)
# 2 = Block (prevents tool execution)
# 3 = Error (non-blocking, indicates script failure)
EXIT_SUCCESS=0
EXIT_WARN=1
EXIT_BLOCK=2
EXIT_ERROR=3

