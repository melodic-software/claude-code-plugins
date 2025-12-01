#!/usr/bin/env bash
# suggest-gemini-docs.sh - Detect Gemini CLI topics and inject docs reminder
#
# TWO-TIER DETECTION:
# - Tier 1 (high-confidence): Unique Gemini CLI terms - always fire
# - Tier 2 (low-confidence): Generic terms - only fire if "gemini" in prompt
#
# This prevents false positives on generic prompts

set -euo pipefail

# Check if hook is enabled (default: enabled)
# To disable: Set CLAUDE_HOOK_SUGGEST_GEMINI_DOCS_ENABLED=0
if [ "${CLAUDE_HOOK_SUGGEST_GEMINI_DOCS_ENABLED:-1}" != "1" ] && \
   [ "${CLAUDE_HOOK_SUGGEST_GEMINI_DOCS_ENABLED:-true}" != "true" ]; then
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

# Check ecosystem context - exit early if Claude is clearly dominant
ECOSYSTEM=$(get_ecosystem_context "$PROMPT_LOWER")
if [[ "$ECOSYSTEM" == "claude" ]]; then
    [[ "${CLAUDE_HOOK_DEBUG:-}" == "1" ]] && echo "gemini-hook: exiting, claude dominant" >&2
    exit 0  # Let Claude hook handle this
fi

# === TIER 1: HIGH-CONFIDENCE PATTERNS (always match) ===
# These are uniquely Gemini CLI - no false positives possible

TIER1_PATTERNS='gemini.?cli|geminicli\.com|gemini.?code'
TIER1_PATTERNS+='|memport|policy.?engine|trusted.?folder'
TIER1_PATTERNS+='|model.?routing|flash.?vs.?pro|pro.?vs.?flash'
TIER1_PATTERNS+='|token.?caching|prompt.?compression'
TIER1_PATTERNS+='|gemini.?extension|gemini.?theme'
TIER1_PATTERNS+='|gemini.?mcp|gemini.?server'
TIER1_PATTERNS+='|llms\.txt'

# === TIER 2: LOW-CONFIDENCE PATTERNS (need "gemini" context) ===
# Generic terms that could apply to anything - only match if "gemini" in prompt

TIER2_PATTERNS='checkpointing|session|rewind|snapshot'
TIER2_PATTERNS+='|tools?|shell|web.?fetch|web.?search|file.?system'
TIER2_PATTERNS+='|extensions?|plugins?'
TIER2_PATTERNS+='|vscode|vs.?code|jetbrains|intellij|ide.?companion'
TIER2_PATTERNS+='|install|setup|configure|authentication'
TIER2_PATTERNS+='|telemetry|settings|commands?'
TIER2_PATTERNS+='|mcp|model.?context.?protocol'
TIER2_PATTERNS+='|memory.?tool|sandbox|security'
TIER2_PATTERNS+='|quickstart|getting.?started'

# === DETECTION LOGIC ===

# Check if "gemini" appears anywhere (for tier 2)
HAS_GEMINI_CONTEXT=false
if [[ $PROMPT_LOWER =~ gemini ]]; then
    HAS_GEMINI_CONTEXT=true
fi

# Check Tier 1 first (always match)
MATCHED=false
if [[ $PROMPT_LOWER =~ ($TIER1_PATTERNS) ]]; then
    MATCHED=true
fi

# Check Tier 2 only if gemini context exists
if [[ $HAS_GEMINI_CONTEXT == true ]] && [[ $PROMPT_LOWER =~ ($TIER2_PATTERNS) ]]; then
    MATCHED=true
fi

# Early exit if no match
if [[ $MATCHED == false ]]; then
    exit 0
fi

# === TOPIC DETECTION ===
TOPIC="gemini-cli"
KEYWORDS="Gemini CLI documentation"

# Check specific categories (most specific first)
if [[ $PROMPT_LOWER =~ (checkpointing|rewind|snapshot|session) ]]; then
    TOPIC="checkpointing"; KEYWORDS="checkpointing, session management, rewind"
elif [[ $PROMPT_LOWER =~ (model.?routing|flash|pro) ]]; then
    TOPIC="model-routing"; KEYWORDS="model routing, Flash vs Pro"
elif [[ $PROMPT_LOWER =~ (token.?caching|prompt.?compression) ]]; then
    TOPIC="token-caching"; KEYWORDS="token caching, cost optimization"
elif [[ $PROMPT_LOWER =~ (policy.?engine|trusted.?folder) ]]; then
    TOPIC="policy-engine"; KEYWORDS="policy engine, trusted folders"
elif [[ $PROMPT_LOWER =~ (memport) ]]; then
    TOPIC="memport"; KEYWORDS="memory import/export"
elif [[ $PROMPT_LOWER =~ (mcp|model.?context.?protocol) ]]; then
    TOPIC="mcp"; KEYWORDS="MCP servers, Model Context Protocol"
elif [[ $PROMPT_LOWER =~ (extension) ]]; then
    TOPIC="extensions"; KEYWORDS="extensions, plugins"
elif [[ $PROMPT_LOWER =~ (tool|shell|web.?fetch|file.?system) ]]; then
    TOPIC="tools"; KEYWORDS="tools API, shell, web fetch"
elif [[ $PROMPT_LOWER =~ (vs.?code|vscode|jetbrains|ide) ]]; then
    TOPIC="ide-integration"; KEYWORDS="VS Code, JetBrains, IDE companion"
elif [[ $PROMPT_LOWER =~ (install|setup|configure|authentication) ]]; then
    TOPIC="installation"; KEYWORDS="installation, setup, authentication"
elif [[ $PROMPT_LOWER =~ (settings|telemetry|theme) ]]; then
    TOPIC="configuration"; KEYWORDS="settings, themes, telemetry"
elif [[ $PROMPT_LOWER =~ (commands?) ]]; then
    TOPIC="commands"; KEYWORDS="CLI commands"
elif [[ $PROMPT_LOWER =~ (quickstart|getting.?started) ]]; then
    TOPIC="quickstart"; KEYWORDS="quickstart, getting started"
fi

# === OUTPUT ===
CONTEXT="<system-reminder>
GEMINI CLI DOCUMENTATION REQUIREMENT DETECTED.

Topic: $TOPIC
Skill: gemini-cli-docs
Keywords: $KEYWORDS

ACTION: Invoke gemini-cli-docs skill before answering.
</system-reminder>"

# Escape for JSON
CONTEXT_ESC="${CONTEXT//\\/\\\\}"
CONTEXT_ESC="${CONTEXT_ESC//\"/\\\"}"
CONTEXT_ESC="${CONTEXT_ESC//$'\n'/\\n}"

printf '{"systemMessage":"gemini-cli-docs: [%s] detected","hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$TOPIC" "$CONTEXT_ESC"
