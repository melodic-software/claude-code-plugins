# shellcheck shell=bash
# hook::refuse for the guardrails guards that stop a destructive command
# (block-dangerous-git, block-root-delete-target). Sourced after hook-utils.sh;
# never executed on its own.
#
#   hook::refuse <reason>
#
# When a person is at the session, the reason goes to them as a PreToolUse
# `permissionDecision: "ask"` document and the guard exits 0, so they decide.
# Otherwise the reason goes to stderr and the guard exits 2, a deny. Never
# returns.
#
# "A person is at the session" means CLAUDE_CODE_SESSION_ATTENDED is exactly
# `1`: an interactive session reads 1, and `claude -p` and `claude --bg` read 0
# (probed 2026-10-15, Claude Code 2.1.301). Any other value, or none, denies,
# so a CI lane that sets nothing never receives a prompt it cannot answer.
# Pointer: the decision fields are in
# https://code.claude.com/docs/en/hooks#pretooluse-decision-control. As of:
# 2026-10-15. Recheck trigger: that section renames `permissionDecision` or its
# `ask` value, or a launch shape without a person starts reading 1.
#
# Under run-guards.sh the ask document is merged with the other guards' output
# (deny over ask), and any guard's exit 2 still denies the call.

hook::refuse_asks() {
  [[ "${CLAUDE_CODE_SESSION_ATTENDED-}" == 1 ]]
}

hook::refuse() {
  if hook::refuse_asks; then
    local __rf_reason
    hook::json_escape_to __rf_reason "$1"
    hook::emit_document '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"'"$__rf_reason"'"}}'
    exit 0
  fi
  printf '%s\n' "$1" >&2
  exit 2
}
