#!/usr/bin/env bash
set -uo pipefail

export LC_ALL=C

[[ "${CLAUDE_PLUGIN_OPTION_PR_LINKAGE_MCP_GATE_ENABLED:-true}" == "true" ]] || exit 0
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
start=${EPOCHREALTIME:-}

hook::buffer_stdin_to INPUT || exit 0
[[ -n "$INPUT" ]] || exit 0

hook::require jq "PreToolUse" "source-control" "$INPUT"

read_fields_singly() {
  local f v
  HOOK_JQ_FIELDS=()
  for f in '.tool_name // empty' '.cwd // empty' \
    '.tool_input.owner // empty' '.tool_input.repo // empty' \
    '.tool_input | has("body")' \
    '(.tool_input.body // "") | tostring | contains("\r")' \
    '.tool_input.body // ""'; do
    v=$(printf '%s' "$INPUT" | jq -r "$f" 2>/dev/null)
    HOOK_JQ_FIELDS+=("$v")
  done
  HOOK_JQ_FIELDS[1]="${HOOK_JQ_FIELDS[1]//$'\r'/}"
}
hook::jq_fields "$INPUT" \
  '.tool_name' '.cwd' '.tool_input.owner' '.tool_input.repo' \
  '(.tool_input | has("body"))' \
  '((.tool_input.body // "") | tostring | contains("\r"))' \
  '(.tool_input.body // "")' || read_fields_singly
TOOL="${HOOK_JQ_FIELDS[0]}"
HOOK_CWD="${HOOK_JQ_FIELDS[1]}"
T_OWNER="${HOOK_JQ_FIELDS[2]}"
T_REPO="${HOOK_JQ_FIELDS[3]}"
HAS_BODY="${HOOK_JQ_FIELDS[4]}"
BODY_HAS_CR="${HOOK_JQ_FIELDS[5]}"
BODY="${HOOK_JQ_FIELDS[6]}"

chomp() {
  local __v="${!1}"
  while [[ "$__v" == *$'\n' ]]; do __v="${__v%$'\n'}"; done
  printf -v "$1" '%s' "$__v"
}
for v in TOOL HOOK_CWD T_OWNER T_REPO BODY; do chomp "$v"; done

IS_UPDATE=0
case "$TOOL" in
mcp__github__create_pull_request | mcp__plugin_*_github__create_pull_request) ;;
mcp__github__update_pull_request | mcp__plugin_*_github__update_pull_request) IS_UPDATE=1 ;;
*) exit 0 ;;
esac

REPO_ROOT=""
hook::repo_root_to REPO_ROOT "${HOOK_CWD:-${CLAUDE_PROJECT_DIR:-.}}" || :

# shellcheck source=pr-linkage-scope.sh
source "$HOOK_DIR/pr-linkage-scope.sh"
GATE_FILE=""
linkage::gate_file_to GATE_FILE "$REPO_ROOT" "pr-linkage-mcp-gate"
[[ -n "$GATE_FILE" ]] || exit 0

{ ORIGIN=$(hook::git_untrusted -C "$REPO_ROOT" remote get-url origin) || ORIGIN=""; } 2>/dev/null
[[ -n "$ORIGIN" && -n "$T_OWNER" && -n "$T_REPO" ]] || exit 0
norm="${ORIGIN%/}"
norm="${norm%.git}"
norm="${norm//:/\/}"
[[ "${norm,,}" == *"/${T_OWNER,,}/${T_REPO,,}" ]] || exit 0

((IS_UPDATE)) && [[ "$HAS_BODY" != "true" ]] && exit 0

if [[ "$BODY_HAS_CR" == "true" ]]; then
  BODY=$(printf '%s' "$INPUT" | jq -r '.tool_input.body // ""' 2>/dev/null)
fi

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data
  hook::json_str_object_to data outcome "$1" tool "$TOOL"
  hook::emit_telemetry "pr-linkage-mcp-gate" "PreToolUse" "${2:-$1}" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

if [[ -f "$REPO_ROOT/.claude/settings.json" ]] &&
  jq -e '[.hooks.PreToolUse[]?.hooks[]? | (.command // empty), (.args[]? | strings)]
    | any(contains("pr-linkage-mcp-gate"))' \
    "$REPO_ROOT/.claude/settings.json" >/dev/null 2>&1; then
  emit_tel "deferred" "skipped"
  exit 0
fi

# shellcheck source=pr-linkage-validator.sh
source "$HOOK_DIR/pr-linkage-validator.sh"
# shellcheck disable=SC2310  # the return status IS the verdict
if linkage::blocking_problems "$BODY"; then
  emit_tel "ok"
  exit 0
fi

linkage::block_message "${GATE_FILE#"$REPO_ROOT/"}"
emit_tel "blocked"
exit 2
