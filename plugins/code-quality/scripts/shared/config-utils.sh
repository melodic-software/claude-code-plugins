#!/usr/bin/env bash
# config-utils.sh - Configuration utilities for Claude Code hooks
#
# Provides logging, configuration, and utility functions for hooks.
# Configuration is handled via environment variables (no external config files).
#
# Usage: Source this file in your hook script: source "${PLUGIN_ROOT}/scripts/shared/config-utils.sh"

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
# Example: is_hook_enabled "MARKDOWN_LINT" || exit 0
# Set CLAUDE_HOOK_DISABLED_MARKDOWN_LINT=1 to disable
is_hook_enabled() {
    local hook_name="$1"
    local env_var="CLAUDE_HOOK_DISABLED_${hook_name}"

    # Check if explicitly disabled via environment variable
    if [ "${!env_var:-}" = "1" ] || [ "${!env_var:-}" = "true" ]; then
        return 1
    fi

    return 0
}

# Load enforcement mode for a hook
# Usage: mode=$(load_enforcement_mode)
# Returns: block, warn, or log
# Configure via CLAUDE_HOOK_ENFORCEMENT_MARKDOWN_LINT env var
load_enforcement_mode() {
    # Default to "warn" (non-blocking) for PostToolUse hooks
    # Users can override via environment variable
    echo "${CLAUDE_HOOK_ENFORCEMENT_MARKDOWN_LINT:-warn}"
}

# Load a message template
# Usage: msg=$(load_message "" "messages.tool_missing")
# Usage: msg=$(load_message "" "messages.unfixable_errors" "count:5" "file_path:README.md")
# First argument is ignored (legacy config file parameter)
load_message() {
    local config_file="$1"  # Ignored - messages are inline
    local message_key="$2"
    shift 2

    case "$message_key" in
        "messages.tool_missing")
            echo "markdownlint-cli2 not installed. Install with: npm install -g markdownlint-cli2"
            ;;
        "messages.unfixable_errors")
            local count="" file_path=""
            for arg in "$@"; do
                case "$arg" in
                    count:*) count="${arg#count:}" ;;
                    file_path:*) file_path="${arg#file_path:}" ;;
                esac
            done
            echo "Found ${count} unfixable markdown error(s) in ${file_path}"
            ;;
        "messages.error_details")
            local errors=""
            for arg in "$@"; do
                case "$arg" in
                    errors:*) errors="${arg#errors:}" ;;
                esac
            done
            echo "Errors: ${errors}"
            ;;
        "messages.suggestion")
            echo "Fix these errors manually or adjust .markdownlint-cli2.jsonc rules."
            ;;
        "messages.documentation")
            echo "See markdownlint rules: https://github.com/DavidAnson/markdownlint/blob/main/doc/Rules.md"
            ;;
        *)
            echo ""
            ;;
    esac
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
