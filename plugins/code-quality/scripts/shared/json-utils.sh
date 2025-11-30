#!/usr/bin/env bash
# json-utils.sh - JSON parsing utilities for Claude Code hooks
#
# This file provides reusable JSON parsing functions for bash-based hooks.
# All hooks receive JSON input via stdin from Claude Code.
#
# Dependencies: jq (JSON processor)
# Usage: Source this file in your hook script: source "${PLUGIN_ROOT}/scripts/shared/json-utils.sh"

set -euo pipefail

# Parse a field from JSON input on stdin
# Usage: echo "$json" | parse_json_field "field.nested.path"
# Returns: The value of the field, or empty string if not found
# Exit codes: 0 = success, 1 = field not found (empty), 3 = JSON parse error
parse_json_field() {
    local field_path="$1"
    local result
    local exit_code

    # Capture both output and exit code
    result=$(jq -r ".${field_path} // empty" 2>&1)
    exit_code=$?

    if [ $exit_code -ne 0 ]; then
        # jq failed - likely malformed JSON
        echo "ERROR: JSON parse failed: $result" >&2
        return 3
    fi

    echo "$result"
    return 0
}

# Parse tool name from hook payload
# Usage: tool_name=$(echo "$json" | get_tool_name)
get_tool_name() {
    parse_json_field "tool_name"
}

# Parse file_path from hook payload (for Write/Edit tools)
# Usage: file_path=$(echo "$json" | get_file_path)
get_file_path() {
    parse_json_field "tool_input.file_path"
}

# Parse command from hook payload (for Bash tool)
# Usage: command=$(echo "$json" | get_command)
get_command() {
    parse_json_field "tool_input.command"
}

# Parse content from hook payload (for Write tool)
# Usage: content=$(echo "$json" | get_content)
get_content() {
    parse_json_field "tool_input.content"
}

# Parse new_string from hook payload (for Edit tool)
# Usage: content=$(echo "$json" | get_new_string)
get_new_string() {
    parse_json_field "tool_input.new_string"
}

# Output JSON decision control for PreToolUse hooks (official schema)
# Usage: output_json_decision "allow|deny|ask" "Reason message"
# Options: allow, deny, ask
#
# IMPORTANT: This uses the official hookSpecificOutput schema per Anthropic docs.
# The deprecated {decision, message} format should NOT be used.
# See: https://code.claude.com/docs/en/hooks
output_json_decision() {
    local decision="$1"      # allow, deny, ask
    local reason="${2:-}"

    jq -n \
        --arg decision "$decision" \
        --arg reason "$reason" \
        '{
          hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: $decision,
            permissionDecisionReason: $reason
          }
        }'
}

# Output JSON error response
# Usage: output_json_error "Error message" "Optional suggestion"
output_json_error() {
    local error="$1"
    local suggestion="${2:-}"

    if [ -n "$suggestion" ]; then
        jq -n \
            --arg error "$error" \
            --arg suggestion "$suggestion" \
            '{error: $error, suggestion: $suggestion}'
    else
        jq -n \
            --arg error "$error" \
            '{error: $error}'
    fi
}

# Output JSON success response
# Usage: output_json_success "Success message"
output_json_success() {
    local message="$1"
    jq -n \
        --arg message "$message" \
        '{success: true, message: $message}'
}

# Check if jq is available
# Usage: check_jq_available || exit 1
check_jq_available() {
    if ! command -v jq &> /dev/null; then
        echo "ERROR: jq is not installed. Please install jq to use this hook." >&2
        return 1
    fi
    return 0
}

# Pretty print JSON for debugging
# Usage: echo "$json" | pretty_print_json
pretty_print_json() {
    local result
    local exit_code

    result=$(jq '.' 2>&1)
    exit_code=$?

    if [ $exit_code -ne 0 ]; then
        echo "ERROR: Invalid JSON: $result" >&2
        cat  # Pass through original input
        return 3
    fi

    echo "$result"
    return 0
}

# Validate JSON input (use at start of hook to fail closed on malformed input)
# Usage: echo "$json" | validate_json || exit 3
# Exit codes: 0 = valid JSON, 3 = invalid JSON
validate_json() {
    local input
    input=$(cat)

    if ! echo "$input" | jq -e '.' > /dev/null 2>&1; then
        echo "ERROR: Invalid JSON input - hook cannot process malformed payload" >&2
        return 3
    fi

    # Output the validated JSON for piping
    echo "$input"
    return 0
}
