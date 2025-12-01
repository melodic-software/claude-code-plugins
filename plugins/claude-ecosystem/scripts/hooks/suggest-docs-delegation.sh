#!/usr/bin/env bash
# suggest-docs-delegation.sh - Detect Claude Code topics and inject docs reminder
#
# TWO-TIER DETECTION:
# - Tier 1 (high-confidence): Unique Claude Code terms - always fire
# - Tier 2 (low-confidence): Generic terms - only fire if "claude" in prompt
#
# This prevents false positives on generic prompts like "install docker" or "github rate limits"

set -euo pipefail

# Check if hook is enabled (default: enabled)
# To disable: Set CLAUDE_HOOK_SUGGEST_DOCS_DELEGATION_ENABLED=0
if [ "${CLAUDE_HOOK_SUGGEST_DOCS_DELEGATION_ENABLED:-1}" != "1" ] && \
   [ "${CLAUDE_HOOK_SUGGEST_DOCS_DELEGATION_ENABLED:-true}" != "true" ]; then
    exit 0
fi

# === FAST PATH: Read input and extract prompt ===
INPUT=$(cat)

if command -v jq &>/dev/null; then
    PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null) || PROMPT=""
else
    PROMPT=$(echo "$INPUT" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' 2>/dev/null) || PROMPT=""
fi

[[ -z "$PROMPT" ]] && exit 0

# Bash 4+ builtin lowercase (no subprocess)
PROMPT_LOWER="${PROMPT,,}"

# === ECOSYSTEM SCORING FUNCTION ===
# Prevents cross-ecosystem misfires by detecting which ecosystem the user is asking about
# Returns: "claude", "gemini", or "ambiguous"

get_ecosystem_context() {
    local prompt_lower="$1"
    local gemini_score=0
    local claude_score=0

    # HIGH-WEIGHT SIGNALS (explicit product mentions) - 10 points each
    [[ $prompt_lower =~ gemini.?cli ]] && ((gemini_score+=10))
    [[ $prompt_lower =~ geminicli ]] && ((gemini_score+=10))
    [[ $prompt_lower =~ google.?gemini ]] && ((gemini_score+=10))
    [[ $prompt_lower =~ geminicli\.com ]] && ((gemini_score+=10))

    [[ $prompt_lower =~ claude[[:space:]]code ]] && ((claude_score+=10))
    [[ $prompt_lower =~ anthropic ]] && ((claude_score+=10))

    # MEDIUM-WEIGHT SIGNALS (config paths, unique terms) - 5 points each
    # Gemini-unique signals
    [[ $prompt_lower =~ \.gemini/ ]] && ((gemini_score+=5))
    [[ $prompt_lower =~ ~/\.gemini ]] && ((gemini_score+=5))
    [[ $prompt_lower =~ gemini\.md ]] && ((gemini_score+=5))
    [[ $prompt_lower =~ \.geminiignore ]] && ((gemini_score+=5))
    [[ $prompt_lower =~ memport ]] && ((gemini_score+=5))
    [[ $prompt_lower =~ trusted.?folder ]] && ((gemini_score+=5))
    [[ $prompt_lower =~ policy.?engine ]] && ((gemini_score+=5))
    [[ $prompt_lower =~ llms\.txt ]] && ((gemini_score+=5))
    [[ $prompt_lower =~ model.?routing ]] && ((gemini_score+=5))
    [[ $prompt_lower =~ token.?caching ]] && ((gemini_score+=5))
    [[ $prompt_lower =~ prompt.?compression ]] && ((gemini_score+=5))
    [[ $prompt_lower =~ /compress ]] && ((gemini_score+=5))
    [[ $prompt_lower =~ /chat[[:space:]]+(save|resume|delete|share) ]] && ((gemini_score+=5))
    [[ $prompt_lower =~ --yolo ]] && ((gemini_score+=5))
    [[ $prompt_lower =~ shadow.?git ]] && ((gemini_score+=5))
    [[ $prompt_lower =~ checkpointing\.enabled ]] && ((gemini_score+=5))
    [[ $prompt_lower =~ gemini_api_key ]] && ((gemini_score+=5))
    [[ $prompt_lower =~ permissive-open|permissive-closed|restrictive-open ]] && ((gemini_score+=5))
    [[ $prompt_lower =~ sandbox-exec|seatbelt ]] && ((gemini_score+=5))

    # Claude-unique signals
    [[ $prompt_lower =~ \.claude/ ]] && ((claude_score+=5))
    [[ $prompt_lower =~ claude\.md ]] && ((claude_score+=5))
    [[ $prompt_lower =~ \.claude-plugin ]] && ((claude_score+=5))
    [[ $prompt_lower =~ settings\.local\.json ]] && ((claude_score+=5))
    [[ $prompt_lower =~ pretooluse|posttooluse|userpromptsubmit ]] && ((claude_score+=5))
    [[ $prompt_lower =~ sessionstart|sessionend|precompact|subagentstop ]] && ((claude_score+=5))
    [[ $prompt_lower =~ allowed-?tools|disallowed-?tools ]] && ((claude_score+=5))
    [[ $prompt_lower =~ permission-?mode|bypasspermissions|acceptedits ]] && ((claude_score+=5))
    [[ $prompt_lower =~ agent-?sdk ]] && ((claude_score+=5))
    [[ $prompt_lower =~ /doctor|/compact|/cost|/statusline|/terminal-setup ]] && ((claude_score+=5))
    [[ $prompt_lower =~ /output-style|/permissions|/memory|/plugin ]] && ((claude_score+=5))
    [[ $prompt_lower =~ managed-settings\.json|managed-mcp\.json ]] && ((claude_score+=5))
    [[ $prompt_lower =~ --dangerously|--permission-prompt-tool ]] && ((claude_score+=5))

    # LOW-WEIGHT SIGNALS (generic but associated terms) - 2 points each
    [[ $prompt_lower =~ gemini ]] && ((gemini_score+=2))
    [[ $prompt_lower =~ claude ]] && ((claude_score+=2))

    # Debug logging (controlled by environment variable)
    if [[ "${CLAUDE_HOOK_DEBUG:-}" == "1" ]]; then
        echo "ecosystem_score: claude=$claude_score gemini=$gemini_score" >&2
    fi

    # DECISION LOGIC
    # Require a significant lead (>5 points) to declare a winner
    if ((gemini_score > claude_score + 5)); then
        echo "gemini"
    elif ((claude_score > gemini_score + 5)); then
        echo "claude"
    else
        echo "ambiguous"
    fi
}

# Check ecosystem context - exit early if Gemini is clearly dominant
ECOSYSTEM=$(get_ecosystem_context "$PROMPT_LOWER")
if [[ "$ECOSYSTEM" == "gemini" ]]; then
    [[ "${CLAUDE_HOOK_DEBUG:-}" == "1" ]] && echo "claude-hook: exiting, gemini dominant" >&2
    exit 0  # Let Gemini hook handle this
fi

# === TIER 1: HIGH-CONFIDENCE PATTERNS (always match) ===
# These are uniquely Claude Code - no false positives possible
# Updated skill names to match new naming convention

TIER1_PATTERNS='hook-management|memory-management|skill-development|subagent-development|plugin-development|mcp-integration|settings-management|sandbox-configuration|permission-management|enterprise-security|output-customization|status-line-customization|agent-sdk-development|command-development|docs-management'
TIER1_PATTERNS+='|pretooluse|posttooluse|userpromptsubmit|sessionstart|sessionend|precompact|subagentstop'
TIER1_PATTERNS+='|claude\.md|\.claude/|\.claude-plugin'
TIER1_PATTERNS+='|allowed-tools|yaml.?frontmatter|skill\.md'
TIER1_PATTERNS+='|sub-?agent|agent.?file|agent.?yaml'
TIER1_PATTERNS+='|model.?context.?protocol|mcp.?server'
TIER1_PATTERNS+='|/output-style|/statusline|/rewind|/cost|/model|/terminal-setup|/compact'
TIER1_PATTERNS+='|--allowedtools|--disallowedtools|--permission-mode|--dangerously'
TIER1_PATTERNS+='|claude.?code|anthropic'

# === TIER 2: LOW-CONFIDENCE PATTERNS (need "claude" context) ===
# Generic terms that could apply to anything - only match if "claude" in prompt

TIER2_PATTERNS='cost|billing|pricing|spend|subscription'
TIER2_PATTERNS+='|rate.?limit|tpm|rpm|quota'
TIER2_PATTERNS+='|analytics|usage|token.?usage|developer.?day'
TIER2_PATTERNS+='|error|debug|troubleshoot|install|setup|configure'
TIER2_PATTERNS+='|hooks?|plugins?|skills?|agents?|commands?'
TIER2_PATTERNS+='|vscode|vs.?code|jetbrains|intellij|ide'
TIER2_PATTERNS+='|docker|devcontainer|container|terminal'
TIER2_PATTERNS+='|proxy|network|gateway|certificate|mtls|firewall'
TIER2_PATTERNS+='|github|gitlab|ci/?cd|actions?|workflow'
TIER2_PATTERNS+='|headless|programmatic|automation|non-interactive'
TIER2_PATTERNS+='|sonnet|opus|haiku|model'
TIER2_PATTERNS+='|bedrock|vertex|foundry|aws|gcp|azure'
TIER2_PATTERNS+='|checkpoint|rewind|session|memory'
TIER2_PATTERNS+='|sandbox|security|permission'
TIER2_PATTERNS+='|quickstart|getting.?started'

# === DETECTION LOGIC ===

# Check if "claude" appears anywhere (for tier 2)
HAS_CLAUDE_CONTEXT=false
if [[ $PROMPT_LOWER =~ claude ]]; then
    HAS_CLAUDE_CONTEXT=true
fi

# Check Tier 1 first (always match)
MATCHED=false
if [[ $PROMPT_LOWER =~ ($TIER1_PATTERNS) ]]; then
    MATCHED=true
fi

# Check Tier 2 only if claude context exists
if [[ $HAS_CLAUDE_CONTEXT == true ]] && [[ $PROMPT_LOWER =~ ($TIER2_PATTERNS) ]]; then
    MATCHED=true
fi

# Early exit if no match
if [[ $MATCHED == false ]]; then
    exit 0
fi

# === TOPIC DETECTION ===
# Updated to use new skill names (noun-phrase pattern)
TOPIC="claude-code"
META_SKILL="docs-management"
KEYWORDS="Claude Code documentation"

# Check specific categories (most specific first)
if [[ $PROMPT_LOWER =~ (hooks?|pretooluse|posttooluse|hook) ]]; then
    TOPIC="hooks"; META_SKILL="hook-management"; KEYWORDS="hooks, PreToolUse, PostToolUse"
elif [[ $PROMPT_LOWER =~ (claude.?plugin|\.claude-plugin|plugin\.json|/plugin\s|marketplace) ]]; then
    TOPIC="plugins"; META_SKILL="plugin-development"; KEYWORDS="plugins, plugin.json"
elif [[ $PROMPT_LOWER =~ (mcp|model.?context.?protocol) ]]; then
    TOPIC="mcp"; META_SKILL="mcp-integration"; KEYWORDS="MCP, MCP servers"
elif [[ $PROMPT_LOWER =~ (skill|yaml.?frontmatter|allowed-tools) ]]; then
    TOPIC="skills"; META_SKILL="skill-development"; KEYWORDS="skills, YAML frontmatter"
elif [[ $PROMPT_LOWER =~ (sub-?agent|agent.?file) ]]; then
    TOPIC="subagents"; META_SKILL="subagent-development"; KEYWORDS="subagents, agent files"
elif [[ $PROMPT_LOWER =~ (claude\.md|\.claude/) ]]; then
    TOPIC="memory"; META_SKILL="memory-management"; KEYWORDS="CLAUDE.md, static memory"
elif [[ $PROMPT_LOWER =~ (claude.?sandbox|/sandbox|--sandbox|sandbox.?config) ]]; then
    TOPIC="sandbox"; META_SKILL="sandbox-configuration"; KEYWORDS="sandbox, isolation"
elif [[ $PROMPT_LOWER =~ (permission) ]]; then
    TOPIC="permissions"; META_SKILL="permission-management"; KEYWORDS="permissions, allow/deny rules"
elif [[ $PROMPT_LOWER =~ (enterprise|managed.?settings) ]]; then
    TOPIC="enterprise"; META_SKILL="enterprise-security"; KEYWORDS="enterprise, managed policies"
elif [[ $PROMPT_LOWER =~ (settings|config) ]]; then
    TOPIC="configuration"; META_SKILL="settings-management"; KEYWORDS="settings.json, configuration"
elif [[ $PROMPT_LOWER =~ (sdk|typescript.?sdk|python.?sdk) ]]; then
    TOPIC="agent-sdk"; META_SKILL="agent-sdk-development"; KEYWORDS="Agent SDK"
elif [[ $PROMPT_LOWER =~ (cost|billing|rate.?limit|analytics) ]]; then
    TOPIC="costs"; KEYWORDS="costs, billing, rate limits"
elif [[ $PROMPT_LOWER =~ (bedrock|vertex|foundry) ]]; then
    TOPIC="cloud-providers"; KEYWORDS="Bedrock, Vertex AI, Foundry"
elif [[ $PROMPT_LOWER =~ (github|gitlab|ci/?cd) ]]; then
    TOPIC="cicd"; KEYWORDS="GitHub Actions, GitLab CI"
elif [[ $PROMPT_LOWER =~ (vs.?code|vscode|jetbrains|ide) ]]; then
    TOPIC="ide-integration"; KEYWORDS="VS Code, JetBrains"
elif [[ $PROMPT_LOWER =~ (output.?style|/output-style) ]]; then
    TOPIC="output-styles"; META_SKILL="output-customization"; KEYWORDS="output styles"
elif [[ $PROMPT_LOWER =~ (status.?line|/statusline) ]]; then
    TOPIC="status-line"; META_SKILL="status-line-customization"; KEYWORDS="status line"
elif [[ $PROMPT_LOWER =~ (slash.?command|\.claude/commands) ]]; then
    TOPIC="slash-commands"; META_SKILL="command-development"; KEYWORDS="slash commands"
elif [[ $PROMPT_LOWER =~ (troubleshoot|error|debug|install) ]]; then
    TOPIC="troubleshooting"; KEYWORDS="troubleshooting, debugging"
elif [[ $PROMPT_LOWER =~ (headless|non-interactive|programmatic) ]]; then
    TOPIC="headless"; KEYWORDS="headless mode"
elif [[ $PROMPT_LOWER =~ (checkpoint|/rewind|session) ]]; then
    TOPIC="checkpointing"; KEYWORDS="checkpointing, rewinding"
elif [[ $PROMPT_LOWER =~ (sonnet|opus|haiku|/model) ]]; then
    TOPIC="model-config"; KEYWORDS="model selection"
elif [[ $PROMPT_LOWER =~ (devcontainer|docker|terminal) ]]; then
    TOPIC="dev-environment"; KEYWORDS="devcontainer, Docker, terminal"
elif [[ $PROMPT_LOWER =~ (proxy|network|gateway|mtls) ]]; then
    TOPIC="network-enterprise"; KEYWORDS="proxy, network, mTLS"
elif [[ $PROMPT_LOWER =~ (quickstart|getting.?started) ]]; then
    TOPIC="quickstart"; KEYWORDS="quickstart, getting started"
fi

# === OUTPUT ===
CONTEXT="<system-reminder>
CLAUDE CODE DOCUMENTATION REQUIREMENT DETECTED.

Topic: $TOPIC
Meta-skill: $META_SKILL
Keywords: $KEYWORDS

ACTION: Invoke docs-management skill (or $META_SKILL) before answering.
</system-reminder>"

# Escape for JSON
CONTEXT_ESC="${CONTEXT//\\/\\\\}"
CONTEXT_ESC="${CONTEXT_ESC//\"/\\\"}"
CONTEXT_ESC="${CONTEXT_ESC//$'\n'/\\n}"

printf '{"systemMessage":"docs-management: [%s] detected","hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$TOPIC" "$CONTEXT_ESC"
