#!/usr/bin/env bash
# inject-citation-context.sh - Inject source citation requirements at session start
#
# Event: SessionStart
# Purpose: Remind Claude about mandatory source citation requirements
#
# This hook injects context at session start to reinforce citation requirements
# defined in the memory file, ensuring consistent source attribution.

set -euo pipefail

# Read and discard stdin (required but not used for context injection)
cat > /dev/null

# Build context injection message
read -r -d '' CONTEXT_MSG << 'EOF' || true
<source-citation-reminder>
SESSION CITATION REQUIREMENTS ACTIVE

All responses with factual claims MUST cite sources:

- [FILE: path/to/file:L##-L##] - Information from codebase files
- [WEB: url] - Information from web search/fetch
- [MCP: server/tool] - Information from MCP tools
- [TRAINING] - General knowledge (add: "knowledge cutoff Jan 2025, verify if critical")
- [INFERRED: from X] - Conclusions drawn from reasoning

Responses with factual claims MUST end with a Sources section.

Exempt: Procedural statements, error reports, questions, acknowledgments.
</source-citation-reminder>
EOF

# JSON escape function
json_escape() {
    local str="$1"
    # Escape backslashes first
    str="${str//\\/\\\\}"
    # Escape double quotes
    str="${str//\"/\\\"}"
    # Escape newlines
    str="${str//$'\n'/\\n}"
    # Escape carriage returns
    str="${str//$'\r'/}"
    # Escape tabs
    str="${str//$'\t'/\\t}"
    echo "$str"
}

# Escape the context message
ESCAPED_MSG=$(json_escape "$CONTEXT_MSG")

# Output JSON with additionalContext
cat << EOF
{
  "systemMessage": "source-citation: requirements active",
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "$ESCAPED_MSG"
  }
}
EOF

exit 0
