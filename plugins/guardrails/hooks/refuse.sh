# shellcheck shell=bash

HOOK_REFUSE_PENDING=()

# shellcheck source=session-attended.sh
unset -f hook::session_attended
source "${BASH_SOURCE[0]%/*}/session-attended.sh" 2>/dev/null || hook::session_attended() { return 1; }

hook::refuse_unwatched() {
  hook::session_attended && [[ "${GUARDRAILS_SESSION_UNWATCHED-}" == 1 ]]
}

hook::refuse_asks() {
  hook::session_attended && [[ "${GUARDRAILS_SESSION_UNWATCHED-}" != 1 ]]
}

hook::refuse() {
  if hook::refuse_asks; then
    local __rf_r
    for __rf_r in ${HOOK_REFUSE_PENDING[@]+"${HOOK_REFUSE_PENDING[@]}"}; do
      [[ "$__rf_r" == "$1" ]] && return 0
    done
    HOOK_REFUSE_PENDING+=("$1")
    # shellcheck disable=SC2034  # read by abort-boundary.sh's settle
    _GAB_POSTURE=closed
    return 0
  fi
  printf '%s\n' "$1" >&2
  if hook::refuse_unwatched; then
    printf '%s\n' \
      'Nobody is watching this session (GUARDRAILS_SESSION_UNWATCHED=1), so this was refused instead of asked.' \
      'Do not retry it another way. Leave it for a person to run later, and report this command:' \
      "${HOOK_REFUSE_COMMAND-}" >&2
  fi
  exit 2
}

hook::refuse_flush() {
  ((${#HOOK_REFUSE_PENDING[@]})) || return 0
  local __rf_all="" __rf_r __rf_esc
  for __rf_r in "${HOOK_REFUSE_PENDING[@]}"; do
    __rf_all+="${__rf_all:+$'\n\n'}$__rf_r"
  done
  hook::json_escape_to __rf_esc "$__rf_all"
  hook::emit_document '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"'"$__rf_esc"'"}}'
  exit 0
}
