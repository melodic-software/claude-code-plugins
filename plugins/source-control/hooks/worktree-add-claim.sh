#!/usr/bin/env bash
set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_WORKTREE_ADD_CLAIM_ENABLED:-true}" == "true" ]] || exit 0
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
# shellcheck source=worktree-path-lib.sh
source "$HOOK_DIR/worktree-path-lib.sh"
hook::buffer_stdin_to INPUT || exit 0

hook::require jq "PostToolUse" "source-control" "$INPUT"

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
COMMAND="${COMMAND//$'\r'/}"
[[ -n "$COMMAND" ]] || exit 0
[[ "$COMMAND" =~ (^|[^[:alnum:]_.-])[Gg][Ii][Tt][^[:alnum:]_-] ]] || exit 0
[[ "$COMMAND" == *worktree* ]] || exit 0
[[ "$COMMAND" == *add* ]] || exit 0

HOOK_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
HOOK_CWD="${HOOK_CWD//$'\r'/}"
SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
SESSION="${SESSION//$'\r'/}"

CLAIM="$HOOK_DIR/../scripts/worktree-claim.sh"
[[ -f "$CLAIM" ]] || exit 0

CLAIM_TARGETS=()

# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
collect_add() {
  local abs
  # shellcheck disable=SC2310  # the return status IS the verdict; abs is read only on 0
  if worktree_add_target_to abs collect_add "$HOOK_CWD" "$@"; then
    CLAIM_TARGETS+=("$abs")
  fi
  return 0
}

HOOK_BPS_FAIL_OPEN=1
hook::bash_parse_segments "$COMMAND" collect_add
HOOK_BPS_FAIL_OPEN=0

((${#CLAIM_TARGETS[@]})) || exit 0

foreign=""

for target in "${CLAIM_TARGETS[@]}"; do
  args=(claim "$target" ${SESSION:+--session-id "$SESSION"})
  claim_rc=0
  { bash "$CLAIM" "${args[@]}" >/dev/null; } 2>/dev/null || claim_rc=$?
  [[ "$claim_rc" -eq 4 ]] && foreign+="${foreign:+, }$target"
done

if [[ -n "$foreign" ]]; then
  hook::emit_channels PostToolUse "source-control: $foreign already carries another session's live claim; it was not claimed for this session." ""
fi

exit 0
