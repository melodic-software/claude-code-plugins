#!/usr/bin/env bash
# suggest-official-docs-delegation.sh - Detect Claude Code ecosystem questions and inject reminder
#
# Event: UserPromptSubmit
# Purpose: Remind Claude to use official-docs skill for Claude Code questions
#
# Exit Codes:
#   0 - Success (always allows prompt, may inject context)

set -euo pipefail

# Get plugin root directory (two levels up from this script)
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Source shared utilities (optional, graceful fallback if not available)
source "${PLUGIN_ROOT}/hooks/shared/json-utils.sh" 2>/dev/null || true
source "${PLUGIN_ROOT}/hooks/shared/config-utils.sh" 2>/dev/null || true

# Check if hook is enabled
if command -v is_hook_enabled &>/dev/null && ! is_hook_enabled "SUGGEST_CLAUDE_DOCS_DELEGATION"; then
    exit 0
fi

# Read JSON input from stdin
INPUT=$(cat)

# Extract prompt text
PROMPT=""
if command -v jq &>/dev/null; then
    PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || echo "")
else
    # Fallback: basic extraction without jq (portable, no grep -oP)
    PROMPT=$(echo "$INPUT" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' 2>/dev/null || echo "")
fi

# If no prompt, exit silently
if [ -z "$PROMPT" ]; then
    exit 0
fi

# Convert to lowercase for pattern matching
PROMPT_LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

# Detection results
DETECTED_TOPICS=()
DETECTED_META_SKILL=""
DETECTED_KEYWORDS=""

# ============================================================================
# Pattern 1: Direct meta-skill mentions
# ============================================================================
if echo "$PROMPT_LOWER" | grep -qE '(hooks-meta|memory-meta|skills-meta|subagents-meta|slash-commands-meta|plugins-meta|mcp-meta|configuration-meta|security-meta|output-styles-meta|status-line-meta|agent-sdk-meta)'; then
    DETECTED_TOPICS+=("meta-skill-direct")
fi

# ============================================================================
# Pattern 2: Hooks-related topics
# ============================================================================
if echo "$PROMPT_LOWER" | grep -qE '\b(hooks?|pretooluse|posttooluse|userpromptsubmit|sessionstart|sessionend|precompact|notification|permissionrequest|subagentstop|hook event|hook config|hooks\.json|hooks\.yaml|hook matcher)\b'; then
    DETECTED_TOPICS+=("hooks")
    DETECTED_META_SKILL="hooks-meta"
    DETECTED_KEYWORDS="hooks, PreToolUse, PostToolUse, hook events, hook configuration, hook matchers"
fi

# ============================================================================
# Pattern 3: Memory/CLAUDE.md related topics
# ============================================================================
if echo "$PROMPT_LOWER" | grep -qE '\b(claude\.md|static memory|memory hierarchy|import syntax|\.claude/memory|progressive disclosure)\b'; then
    DETECTED_TOPICS+=("memory")
    if [ -z "$DETECTED_META_SKILL" ]; then
        DETECTED_META_SKILL="memory-meta"
        DETECTED_KEYWORDS="CLAUDE.md, static memory, memory hierarchy, import syntax, progressive disclosure"
    fi
fi

# ============================================================================
# Pattern 4: Skills-related topics
# ============================================================================
if echo "$PROMPT_LOWER" | grep -qE '\b(agent skill|skill creation|yaml frontmatter|allowed-tools|skill file|create.*skill|skill\.md)\b'; then
    DETECTED_TOPICS+=("skills")
    if [ -z "$DETECTED_META_SKILL" ]; then
        DETECTED_META_SKILL="skills-meta"
        DETECTED_KEYWORDS="skills, agent skills, YAML frontmatter, allowed-tools, skill creation"
    fi
fi

# ============================================================================
# Pattern 5: Subagents-related topics
# ============================================================================
if echo "$PROMPT_LOWER" | grep -qE '\b(subagent|sub-agent|agent file|agent yaml|task tool.*agent|explore agent|plan agent|agent model selection)\b'; then
    DETECTED_TOPICS+=("subagents")
    if [ -z "$DETECTED_META_SKILL" ]; then
        DETECTED_META_SKILL="subagents-meta"
        DETECTED_KEYWORDS="subagents, agent files, Task tool, Explore agent, Plan agent, agent model selection"
    fi
fi

# ============================================================================
# Pattern 6: Slash commands-related topics
# ============================================================================
if echo "$PROMPT_LOWER" | grep -qE '\b(slash command|custom command|\.claude/commands|command\.md)\b'; then
    DETECTED_TOPICS+=("slash-commands")
    if [ -z "$DETECTED_META_SKILL" ]; then
        DETECTED_META_SKILL="slash-commands-meta"
        DETECTED_KEYWORDS="slash commands, custom commands, .claude/commands"
    fi
fi

# ============================================================================
# Pattern 7: Plugins-related topics
# ============================================================================
if echo "$PROMPT_LOWER" | grep -qE '\b(plugin(s)?|plugin\.json|\.claude-plugin|plugin hook|plugin skill|plugin marketplace|marketplace\.json)\b'; then
    DETECTED_TOPICS+=("plugins")
    if [ -z "$DETECTED_META_SKILL" ]; then
        DETECTED_META_SKILL="plugins-meta"
        DETECTED_KEYWORDS="plugins, plugin.json, plugin hooks, plugin skills, marketplace"
    fi
fi

# ============================================================================
# Pattern 8: MCP-related topics
# ============================================================================
if echo "$PROMPT_LOWER" | grep -qE '\b(mcp server|model context protocol|mcp tool|mcp config|mcp resource)\b'; then
    DETECTED_TOPICS+=("mcp")
    if [ -z "$DETECTED_META_SKILL" ]; then
        DETECTED_META_SKILL="mcp-meta"
        DETECTED_KEYWORDS="MCP, MCP servers, Model Context Protocol, MCP tools, MCP configuration"
    fi
fi

# ============================================================================
# Pattern 9: Configuration/Settings-related topics
# ============================================================================
if echo "$PROMPT_LOWER" | grep -qE '\b(settings\.json|\.claude/settings|permission setting|sandbox setting|claude code config|enterprise.*setting)\b'; then
    DETECTED_TOPICS+=("configuration")
    if [ -z "$DETECTED_META_SKILL" ]; then
        DETECTED_META_SKILL="configuration-meta"
        DETECTED_KEYWORDS="settings.json, permissions, sandbox, Claude Code configuration"
    fi
fi

# ============================================================================
# Pattern 10: Security-related topics
# ============================================================================
if echo "$PROMPT_LOWER" | grep -qE '\b(claude code security|sandboxing|iam|permission.*mode|tool.*restriction)\b'; then
    DETECTED_TOPICS+=("security")
    if [ -z "$DETECTED_META_SKILL" ]; then
        DETECTED_META_SKILL="security-meta"
        DETECTED_KEYWORDS="security, sandboxing, IAM, permissions, tool restrictions"
    fi
fi

# ============================================================================
# Pattern 11: Output styles-related topics
# ============================================================================
if echo "$PROMPT_LOWER" | grep -qE '\b(output style|output format|explanatory style|learning style|/output-style)\b'; then
    DETECTED_TOPICS+=("output-styles")
    if [ -z "$DETECTED_META_SKILL" ]; then
        DETECTED_META_SKILL="output-styles-meta"
        DETECTED_KEYWORDS="output styles, output format, explanatory style, learning style"
    fi
fi

# ============================================================================
# Pattern 12: Status line-related topics
# ============================================================================
if echo "$PROMPT_LOWER" | grep -qE '\b(status line|statusline|terminal status)\b'; then
    DETECTED_TOPICS+=("status-line")
    if [ -z "$DETECTED_META_SKILL" ]; then
        DETECTED_META_SKILL="status-line-meta"
        DETECTED_KEYWORDS="status line, terminal status, statusline configuration"
    fi
fi

# ============================================================================
# Pattern 13: Agent SDK-related topics
# ============================================================================
if echo "$PROMPT_LOWER" | grep -qE '\b(agent sdk|typescript sdk|python sdk|claude sdk|sdk session|sdk tool)\b'; then
    DETECTED_TOPICS+=("agent-sdk")
    if [ -z "$DETECTED_META_SKILL" ]; then
        DETECTED_META_SKILL="agent-sdk-meta"
        DETECTED_KEYWORDS="Agent SDK, TypeScript SDK, Python SDK, sessions, custom tools"
    fi
fi

# ============================================================================
# Pattern 14: Generic "how to" questions about Claude Code features
# ============================================================================
if echo "$PROMPT_LOWER" | grep -qE '(how (do|can|to)|what is|explain|help with|set up|configure|create|use).*(claude code|hooks?|skills?|subagents?|mcp|plugins?|memory|claude\.md)'; then
    DETECTED_TOPICS+=("how-to-question")
fi

# If no patterns detected, exit silently (no context injection needed)
if [ ${#DETECTED_TOPICS[@]} -eq 0 ]; then
    exit 0
fi

# Build context injection message
CONTEXT_MSG="<system-reminder>
CLAUDE CODE DOCUMENTATION REQUIREMENT DETECTED in user prompt.

Detected topics: ${DETECTED_TOPICS[*]}

MANDATORY ACTION (per CLAUDE.md rule):
Before answering ANY question about Claude Code features:

1. INVOKE official-docs skill (or appropriate meta-skill) FIRST
2. Load official documentation for the detected topic
3. Base your response 100% on official docs - NEVER rely on memory or assumptions"

# Add meta-skill suggestion if detected
if [ -n "$DETECTED_META_SKILL" ]; then
    CONTEXT_MSG+="

Relevant meta-skill: $DETECTED_META_SKILL
Keywords for official-docs: $DETECTED_KEYWORDS"
fi

CONTEXT_MSG+="

See Claude Code documentation for complete guidance on official-docs skill usage.
</system-reminder>"

# JSON escape function (fallback when jq not available)
json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/}"
    str="${str//$'\t'/\\t}"
    echo "\"$str\""
}

# Build user-visible system message (brief summary of what hook detected)
SYSTEM_MSG="official-docs hook: Detected [${DETECTED_TOPICS[*]}] - context injected"

# Output JSON with both systemMessage (user feedback) and additionalContext (Claude context)
if command -v jq &>/dev/null; then
    ESCAPED_CONTEXT=$(echo "$CONTEXT_MSG" | jq -Rs .)
    ESCAPED_SYSTEM_MSG=$(echo "$SYSTEM_MSG" | jq -Rs .)
else
    ESCAPED_CONTEXT=$(json_escape "$CONTEXT_MSG")
    ESCAPED_SYSTEM_MSG=$(json_escape "$SYSTEM_MSG")
fi

cat << EOF
{
  "systemMessage": $ESCAPED_SYSTEM_MSG,
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": $ESCAPED_CONTEXT
  }
}
EOF

exit 0
