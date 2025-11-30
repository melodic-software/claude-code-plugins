#!/usr/bin/env bash
# inject-current-date.sh - Inject current UTC date/time into Claude's context at session start
#
# Event: SessionStart
# Purpose: Automatically inject current UTC date/time so Claude doesn't need to run date command
#
# Exit Codes:
#   0 - Success (injects date context)
#
# Configuration: Inline (official Claude Code pattern)
# To disable: Set CLAUDE_HOOK_DISABLED_INJECT_CURRENT_DATE=1

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared utilities (optional, may not be loaded for SessionStart)
source "${SCRIPT_DIR}/../../shared/config-utils.sh" 2>/dev/null || true

# Check if hook is enabled
if command -v is_hook_enabled &>/dev/null && ! is_hook_enabled "INJECT_CURRENT_DATE"; then
    exit 0
fi

# Read JSON input from stdin (required but we don't need it)
cat > /dev/null

# Get current UTC date/time in ISO 8601 format
CURRENT_DATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
CURRENT_DATE_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Build context injection message
CONTEXT_MSG="<session-context>
CURRENT DATE/TIME (automatically injected at session start):
- UTC: ${CURRENT_DATE}
- ISO 8601: ${CURRENT_DATE_ISO}

This timestamp is accurate as of session start. For time-sensitive operations requiring the latest time, execute a date command directly.
</session-context>"

# Function to escape JSON string (fallback if jq not available)
json_escape() {
    local str="$1"
    # Escape backslashes, quotes, and newlines
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/}"
    str="${str//$'\t'/\\t}"
    echo "\"$str\""
}

# Output JSON with additionalContext to inject the date
# SessionStart hooks can inject context via additionalContext field
if command -v jq &>/dev/null; then
    ESCAPED_MSG=$(echo "$CONTEXT_MSG" | jq -Rs .)
else
    ESCAPED_MSG=$(json_escape "$CONTEXT_MSG")
fi

cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": $ESCAPED_MSG
  }
}
EOF

exit 0
