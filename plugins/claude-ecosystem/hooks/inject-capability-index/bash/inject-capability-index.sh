#!/usr/bin/env bash
# inject-capability-index.sh - Inject capability index at session start
#
# Event: SessionStart
# Purpose: Provide Claude with complete index of available capabilities
#          (skills, agents, commands) from all installed plugins
#
# Configuration Environment Variables:
#   CLAUDE_HOOK_CAPABILITY_INDEX_ENABLED: 0|1 (default: 1)
#   CLAUDE_HOOK_CAPABILITY_INDEX_MODE: static|cached|dynamic (default: static)
#   CLAUDE_HOOK_CAPABILITY_INDEX_DETAIL: minimal|standard|comprehensive (default: standard)
#
# Generation Modes:
#   static:  Use pre-generated cache only (fastest, manual refresh via /refresh-capability-index)
#   cached:  Check staleness, regenerate if source files changed
#   dynamic: Always regenerate fresh index (slowest, ~500ms)

set -euo pipefail

# Read and discard stdin (required for SessionStart hooks)
cat > /dev/null

# Check if hook is disabled (default: enabled)
if [[ "${CLAUDE_HOOK_CAPABILITY_INDEX_ENABLED:-1}" == "0" ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"SessionStart"}}'
    exit 0
fi

# Configuration with defaults
MODE="${CLAUDE_HOOK_CAPABILITY_INDEX_MODE:-static}"
DETAIL="${CLAUDE_HOOK_CAPABILITY_INDEX_DETAIL:-standard}"

# Get script directory (resolve symlinks)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_DIR="$(dirname "$SCRIPT_DIR")"
PYTHON_SCRIPT="$HOOK_DIR/python/generate_index.py"
CACHE_FILE="$HOOK_DIR/cache/capability-index.txt"

# Find plugins directory (go up to repository root)
find_plugins_dir() {
    local current="$HOOK_DIR"
    for _ in {1..10}; do
        if [[ -d "$current/plugins" ]]; then
            echo "$current/plugins"
            return 0
        fi
        current="$(dirname "$current")"
    done
    return 1
}

# Check if cache is stale (any source file newer than cache)
is_cache_stale() {
    [[ ! -f "$CACHE_FILE" ]] && return 0

    local plugins_dir
    plugins_dir="$(find_plugins_dir)" || return 0

    # Find any SKILL.md, agent .md, plugin.json, or command .md newer than cache
    local newest_source
    newest_source=$(find "$plugins_dir" \
        \( -name "SKILL.md" -o -name "plugin.json" -o -path "*/agents/*.md" -o -path "*/commands/*.md" \) \
        -newer "$CACHE_FILE" -print -quit 2>/dev/null || true)

    [[ -n "$newest_source" ]]
}

# Find Python interpreter
find_python() {
    if command -v python3 &>/dev/null; then
        echo "python3"
    elif command -v python &>/dev/null; then
        echo "python"
    else
        return 1
    fi
}

# Generate index using Python script
generate_index() {
    local python_cmd
    python_cmd="$(find_python)" || return 1

    local plugins_dir
    plugins_dir="$(find_plugins_dir)" || return 1

    # Run Python generator
    local result
    result=$("$python_cmd" "$PYTHON_SCRIPT" --detail "$DETAIL" --plugins-dir "$plugins_dir" --output json 2>/dev/null) || return 1

    # Extract index text from JSON
    echo "$result" | grep -o '"index": "[^"]*"' | sed 's/"index": "//;s/"$//' 2>/dev/null || \
    echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('index',''))" 2>/dev/null || \
    return 1
}

# Main logic based on mode
INDEX_CONTENT=""

case "$MODE" in
    dynamic)
        # Always regenerate
        INDEX_CONTENT=$(generate_index) || INDEX_CONTENT=""
        # Update cache for future static mode use
        if [[ -n "$INDEX_CONTENT" ]]; then
            echo "$INDEX_CONTENT" > "$CACHE_FILE" 2>/dev/null || true
        fi
        ;;

    cached)
        # Check staleness, regenerate if needed
        if is_cache_stale; then
            INDEX_CONTENT=$(generate_index) || INDEX_CONTENT=""
            if [[ -n "$INDEX_CONTENT" ]]; then
                echo "$INDEX_CONTENT" > "$CACHE_FILE" 2>/dev/null || true
            fi
        else
            # Use cache
            INDEX_CONTENT=$(cat "$CACHE_FILE" 2>/dev/null) || INDEX_CONTENT=""
        fi
        ;;

    static|*)
        # Use cache only, skip if missing
        if [[ -f "$CACHE_FILE" ]]; then
            INDEX_CONTENT=$(cat "$CACHE_FILE" 2>/dev/null) || INDEX_CONTENT=""
        fi
        ;;
esac

# If no content available, exit gracefully without injection
if [[ -z "$INDEX_CONTENT" ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"SessionStart"}}'
    exit 0
fi

# JSON escape function (handles newlines, quotes, backslashes, tabs)
json_escape() {
    local str="$1"
    # Escape backslashes first
    str="${str//\\/\\\\}"
    # Escape double quotes
    str="${str//\"/\\\"}"
    # Escape newlines
    str="${str//$'\n'/\\n}"
    # Remove carriage returns
    str="${str//$'\r'/}"
    # Escape tabs
    str="${str//$'\t'/\\t}"
    echo "$str"
}

ESCAPED_CONTENT=$(json_escape "$INDEX_CONTENT")

# Output JSON with additionalContext
cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "$ESCAPED_CONTENT"
  }
}
EOF

exit 0
