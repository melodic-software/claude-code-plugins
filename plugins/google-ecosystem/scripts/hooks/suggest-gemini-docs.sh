#!/usr/bin/env bash
# suggest-gemini-docs.sh - Detect Gemini CLI topics and inject docs reminder
#
# TWO-TIER DETECTION:
# - Tier 1 (high-confidence): Unique Gemini CLI terms - always fire
# - Tier 2 (low-confidence): Generic terms - only fire if "gemini" in prompt
#
# This prevents false positives on generic prompts

set -euo pipefail

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
