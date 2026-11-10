# shellcheck shell=bash
# hook::refuse for the guardrails guards that stop a destructive command
# (block-dangerous-git, block-root-delete-target). Sourced after hook-utils.sh;
# never executed on its own.
#
#   hook::refuse <reason>      refuse one segment
#   hook::refuse_flush         at the guard's normal end, after the whole command
#                              was read: emit the ask, if any, and exit 0
#
# Unattended or unwatched, hook::refuse prints the reason to stderr and exits 2,
# a deny.
# Attended and watched, it records the reason and returns, so the guard reads the rest of
# the command: an ask is only ever the verdict on the WHOLE command. Any later
# deny (another form, a budget, a parse cap, an abort) still ends the guard
# with exit 2, and from the first recorded ask the guard's abort posture is
# closed, so a crash after it denies instead of allowing. hook::refuse_flush
# then names every recorded segment in one PreToolUse `permissionDecision:
# "ask"` document.
#
# "Attended" means CLAUDE_CODE_SESSION_ATTENDED is exactly `1`: an interactive
# session reads 1, and `claude -p` and `claude --bg` read 0 (probed 2026-10-15,
# Claude Code 2.1.301). Any other value, or none, denies, so a CI lane that sets
# nothing never receives a prompt it cannot answer. Pointer: the decision
# fields are in https://code.claude.com/docs/en/hooks#pretooluse-decision-control.
# As of: 2026-10-15. Recheck trigger: that section renames `permissionDecision`
# or its `ask` value, or a launch shape without a person starts reading 1.
#
# "Unwatched" means GUARDRAILS_SESSION_UNWATCHED is exactly `1`: an interactive
# session left running with nobody at it reads ATTENDED=1 all the same, and an
# ask there waits for a prompt nobody answers. The hooks reference documents no
# field or variable that says whether a person is watching, so the session
# declares it: whoever starts it sets the variable in its environment or in a
# settings file's `env`. Unwatched, hook::refuse denies as it does unattended,
# and the reason also names the command for a person to run later
# (HOOK_REFUSE_COMMAND, which the guard sets to the command it read). The
# variable can only turn an ask into a deny, so whoever sets it gains nothing.
#
# Under run-guards.sh the ask document is merged with the other guards' output
# (deny over ask), and any guard's exit 2 still denies the call. Each guard
# sources this file, which resets the record for that guard.

HOOK_REFUSE_PENDING=()

hook::refuse_unwatched() {
  [[ "${CLAUDE_CODE_SESSION_ATTENDED-}" == 1 && "${GUARDRAILS_SESSION_UNWATCHED-}" == 1 ]]
}

hook::refuse_asks() {
  [[ "${CLAUDE_CODE_SESSION_ATTENDED-}" == 1 && "${GUARDRAILS_SESSION_UNWATCHED-}" != 1 ]]
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
