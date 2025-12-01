#!/usr/bin/env bash
# prevent-backup-files.sh - Block creation of .bak and backup files
#
# Event: PreToolUse
# Matcher: Write, Edit
# Purpose: Prevent .bak, .backup, and similar backup files for git-tracked content
#
# Exit Codes:
#   0 - Success (file allowed)
#   2 - Block (backup file detected)
#   3 - Error (missing dependencies, etc.)
#
# Configuration: Inline (official Claude Code pattern)
# To disable: Set CLAUDE_HOOK_PREVENT_BACKUP_FILES_ENABLED=0

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared utilities
source "${SCRIPT_DIR}/../../shared/json-utils.sh" || { echo "ERROR: Cannot load json-utils.sh" >&2; exit 3; }
source "${SCRIPT_DIR}/../../shared/path-utils.sh" || { echo "ERROR: Cannot load path-utils.sh" >&2; exit 3; }
source "${SCRIPT_DIR}/../../shared/config-utils.sh" || { echo "ERROR: Cannot load config-utils.sh" >&2; exit 3; }

# ============================================================================
# INLINE CONFIGURATION (replaces config.yaml)
# ============================================================================

# Enforcement mode: block (default), warn, or log
ENFORCEMENT="block"

# Backup file extensions to block
BACKUP_EXTENSIONS=".bak .backup ~ .orig .swp .swo .tmp"

# Excluded paths (files in these directories are always allowed)
EXCLUDED_PATHS=".git node_modules __pycache__ .claude/temp"

# Error messages
MSG_VIOLATION="Attempted to create backup file"
MSG_REASON="Backup files are not allowed for git-tracked content. They clutter the repository and are not version controlled properly."
MSG_SUGGESTION="If you need to preserve content before changes, use git commits or branches instead."
MSG_WORKAROUND="For temporary files, use .claude/temp/ directory which is gitignored."
MSG_DOC="See CLAUDE.md for file management guidelines."

# ============================================================================
# HOOK LOGIC
# ============================================================================

# Check if hook is enabled (default: enabled)
if ! is_hook_enabled "PREVENT_BACKUP_FILES" "true"; then
    log_message "debug" "prevent-backup-files: Hook disabled, exiting"
    exit 0
fi

# Check dependencies
if ! check_jq_available; then
    echo "ERROR: jq is required but not installed. Please install jq from https://jqlang.github.io/jq/" >&2
    exit 3
fi

# Read JSON input from stdin
INPUT=$(cat)

# Extract tool name and file path
TOOL=$(echo "$INPUT" | get_tool_name)
FILE_PATH=$(echo "$INPUT" | get_file_path)

log_message "debug" "prevent-backup-files: tool=$TOOL, file_path=$FILE_PATH"

# Only check Write and Edit tools
if [[ "$TOOL" != "Write" && "$TOOL" != "Edit" ]]; then
    log_message "debug" "prevent-backup-files: Not a Write/Edit tool, allowing"
    exit 0
fi

# If no file_path, nothing to check
if [ -z "$FILE_PATH" ]; then
    log_message "debug" "prevent-backup-files: No file_path in payload, allowing"
    exit 0
fi

# Check if path is in excluded directories
if is_temp_path "$FILE_PATH" "$EXCLUDED_PATHS"; then
    log_message "debug" "prevent-backup-files: File in excluded path, allowing"
    exit 0
fi

# Check if file has backup extension
if has_extension "$FILE_PATH" "$BACKUP_EXTENSIONS"; then
    # Build error message
    ERROR_MESSAGE="$MSG_VIOLATION: $FILE_PATH

$MSG_REASON

$MSG_SUGGESTION

$MSG_WORKAROUND

$MSG_DOC"

    # Log the violation
    log_message "warn" "prevent-backup-files: Backup file detected: $FILE_PATH"

    # Output based on enforcement mode
    case "$ENFORCEMENT" in
        block)
            echo "$ERROR_MESSAGE" >&2
            log_message "info" "prevent-backup-files: Blocking operation (exit 2)"
            exit 2
            ;;
        warn)
            echo "WARNING: $ERROR_MESSAGE" >&2
            log_message "info" "prevent-backup-files: Warning issued (exit 1)"
            exit 1
            ;;
        log)
            log_message "info" "prevent-backup-files: Logged violation but allowing (exit 0)"
            exit 0
            ;;
        *)
            # Default to block
            echo "$ERROR_MESSAGE" >&2
            exit 2
            ;;
    esac
fi

# File is allowed
log_message "debug" "prevent-backup-files: File allowed"
exit 0
