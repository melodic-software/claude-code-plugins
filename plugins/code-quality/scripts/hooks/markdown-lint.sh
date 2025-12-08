#!/usr/bin/env bash
# markdown-lint.sh - Auto-lint and validate markdown files
#
# Event: PostToolUse
# Matcher: Write, Edit
# Purpose: Automatically fix markdown linting errors and warn about unfixable ones
#
# Exit Codes:
#   0 - Success (no errors or all fixed)
#   1 - Warning (unfixable errors remain, enforcement: warn)
#   2 - Block (unfixable errors, enforcement: block)
#   3 - Error (missing dependencies, etc.)
#
# Environment Variables:
#   CLAUDE_HOOK_MARKDOWN_LINT_ENABLED - Set to 1 to enable hook (default: disabled)
#   CLAUDE_HOOK_ENFORCEMENT_MARKDOWN_LINT - block, warn (default), or log
#   CLAUDE_HOOK_LOG_LEVEL - debug, info (default), warn, or error
#
# NOTE: This hook is DISABLED by default because it requires markdownlint-cli2
# to be installed and configured. Plugin consumers may not have this setup.
# To enable: Set CLAUDE_HOOK_MARKDOWN_LINT_ENABLED=1

set -euo pipefail

# Plugin root with fallback for local testing
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# Source shared utilities from plugin
source "${PLUGIN_ROOT}/scripts/shared/json-utils.sh" || { echo "ERROR: Cannot load json-utils.sh" >&2; exit 3; }
source "${PLUGIN_ROOT}/scripts/shared/path-utils.sh" || { echo "ERROR: Cannot load path-utils.sh" >&2; exit 3; }
source "${PLUGIN_ROOT}/scripts/shared/config-utils.sh" || { echo "ERROR: Cannot load config-utils.sh" >&2; exit 3; }

# Check if hook is enabled (default: disabled - requires external tooling setup)
if ! is_hook_enabled "MARKDOWN_LINT" "false"; then
    log_message "debug" "markdown-lint: Hook disabled (set CLAUDE_HOOK_MARKDOWN_LINT_ENABLED=1 to enable)"
    echo '{"systemMessage":"markdown-lint: disabled"}'
    exit 0
fi

# Check dependencies
if ! check_jq_available; then
    echo "ERROR: jq is required but not installed. Please install jq from https://jqlang.github.io/jq/" >&2
    exit 3
fi

# Check if markdownlint-cli2 is available
if ! command -v npx &> /dev/null; then
    log_message "warn" "markdown-lint: npx not found, cannot run markdownlint-cli2"
    TOOL_MISSING_MSG=$(load_message "" "messages.tool_missing")
    echo "WARNING: $TOOL_MISSING_MSG" >&2
    echo '{"systemMessage":"markdown-lint: skipped (npx missing)"}'
    exit 0  # Allow operation, just warn
fi

# Read JSON input from stdin
INPUT=$(cat)

# Extract tool name and file path
TOOL=$(echo "$INPUT" | get_tool_name)
FILE_PATH=$(echo "$INPUT" | get_file_path)

log_message "debug" "markdown-lint: tool=$TOOL, file_path=$FILE_PATH"

# Only check Write and Edit tools
if [[ "$TOOL" != "Write" && "$TOOL" != "Edit" ]]; then
    log_message "debug" "markdown-lint: Not a Write/Edit tool, allowing"
    echo '{"systemMessage":"markdown-lint: skipped (not Write/Edit)"}'
    exit 0
fi

# If no file_path, nothing to check
if [ -z "$FILE_PATH" ]; then
    log_message "debug" "markdown-lint: No file_path in payload, allowing"
    echo '{"systemMessage":"markdown-lint: skipped (no file path)"}'
    exit 0
fi

# NOTE: File exclusions are handled by .markdownlint-cli2.jsonc (single source of truth)
# markdownlint-cli2 automatically respects the "ignores" section, so we don't pre-filter here

# Check if file is a markdown file
# Note: Hardcoded extensions for reliability without yq dependency
MARKDOWN_EXTENSIONS=".md .mdx .markdown"
log_message "debug" "markdown-lint: Markdown extensions: $MARKDOWN_EXTENSIONS"

if ! has_extension "$FILE_PATH" "$MARKDOWN_EXTENSIONS"; then
    log_message "debug" "markdown-lint: Not a markdown file, allowing"
    echo '{"systemMessage":"markdown-lint: skipped (not markdown)"}'
    exit 0
fi

# Check if file exists (it should, since this is PostToolUse)
if [ ! -f "$FILE_PATH" ]; then
    log_message "warn" "markdown-lint: File does not exist: $FILE_PATH"
    echo '{"systemMessage":"markdown-lint: skipped (file missing)"}'
    exit 0
fi

# Run markdownlint with --fix flag
log_message "debug" "markdown-lint: Running markdownlint --fix on $FILE_PATH"
if npx markdownlint-cli2 --fix "$FILE_PATH" &> /dev/null; then
    log_message "debug" "markdown-lint: Auto-fix completed successfully"
fi

# Check for remaining errors
log_message "debug" "markdown-lint: Checking for unfixable errors"
ERROR_OUTPUT=$(npx markdownlint-cli2 "$FILE_PATH" 2>&1 || true)

# Check if there are actual errors (look for "error MD" pattern)
if ! echo "$ERROR_OUTPUT" | grep -q "error MD"; then
    log_message "debug" "markdown-lint: No errors found, allowing"
    echo '{"systemMessage":"markdown-lint: linting passed"}'
    exit 0
fi

# Count actual error lines (lines containing "error MD")
ERROR_COUNT=$(echo "$ERROR_OUTPUT" | grep -c "error MD" || true)

# Load enforcement mode
ENFORCEMENT=$(load_enforcement_mode)

# Load messages
UNFIXABLE_MSG=$(load_message "" "messages.unfixable_errors" "count:$ERROR_COUNT" "file_path:$FILE_PATH")
ERROR_DETAILS_MSG=$(load_message "" "messages.error_details" "errors:$ERROR_OUTPUT")
SUGGESTION_MSG=$(load_message "" "messages.suggestion")
DOC_MSG=$(load_message "" "messages.documentation")

# Build error message
ERROR_MESSAGE="$UNFIXABLE_MSG

$ERROR_DETAILS_MSG

$SUGGESTION_MSG

$DOC_MSG"

# Log the violation
log_message "warn" "markdown-lint: $ERROR_COUNT unfixable error(s) in $FILE_PATH"
log_message "debug" "markdown-lint: Errors: $ERROR_OUTPUT"

# Output based on enforcement mode
case "$ENFORCEMENT" in
    block)
        echo "$ERROR_MESSAGE" >&2
        log_message "info" "markdown-lint: Blocking due to unfixable errors (exit 2)"
        exit 2
        ;;
    warn)
        echo "WARNING: $ERROR_MESSAGE" >&2
        log_message "info" "markdown-lint: Warning issued (exit 1)"
        exit 1
        ;;
    log)
        log_message "info" "markdown-lint: Logged violation but allowing (exit 0)"
        echo '{"systemMessage":"markdown-lint: errors logged (see debug)"}'
        exit 0
        ;;
    *)
        # Default to warn (non-blocking)
        echo "WARNING: $ERROR_MESSAGE" >&2
        log_message "info" "markdown-lint: Warning issued (exit 1)"
        exit 1
        ;;
esac
