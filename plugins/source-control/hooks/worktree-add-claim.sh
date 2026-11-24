#!/usr/bin/env bash
# worktree-add-claim.sh — PostToolUse hook: after a raw Bash
# `git worktree add`, claim THE parsed add target (#2882).
#
# WHY IT EXISTS — worktree-create.sh arms `git worktree lock` on the trees
# it creates, and the WorktreeCreate hook routes harness-driven creation
# through that helper. A plain `git worktree add` from a Bash tool call
# bypasses both and produces an unlocked tree. The PreToolUse sibling
# (worktree-add-containment-gate.sh) can only judge nesting *before* the
# command runs; locking is only possible after the worktree exists. This
# hook is that after-moment.
#
# WHAT IT CLAIMS — only the worktree path the executed `git worktree add`
# named, parsed with the same tokenizer / `-C` / wrapper-chdir composition
# as the containment gate. `--all-unclaimed` is deliberately not used: if
# two sessions finish `git worktree add` before either PostToolUse runs,
# claiming every unlocked tree would assign both to whichever hook fired
# first. Dynamic targets, a prior `cd`, or a command this hook cannot
# tokenize FAIL OPEN (a missed claim is visible on `report` / `check-enter`).
# `echo git worktree add ...` is not a git call. Existing reasons are never
# rewritten, so helper-created trees keep the `worktree-create.sh: ...`
# string.
#
# FAIL-OPEN. A missed claim is visible on the next `worktree-claim.sh report`
# / `check-enter`; blocking an arbitrary Bash call because this hook could
# not lock is the worse failure. Kill switch:
# worktree_add_claim_enabled.
#
# The lock is a *claim other agents can read*. It does not block concurrent
# writes — git-worktree(1) lock only prevents remove/move/prune.

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_WORKTREE_ADD_CLAIM_ENABLED:-true}" == "true" ]] || exit 0
# Parameter expansion, not `dirname`: a command substitution forks, which is a
# process on Windows Git Bash. A bare filename strips to itself, so it means `.`.
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
# shellcheck source=worktree-path-lib.sh
source "$HOOK_DIR/worktree-path-lib.sh"
hook::buffer_stdin_to INPUT || exit 0

hook::require jq "PostToolUse" "source-control" "$INPUT"

# Fed through `printf '%s' "$INPUT" | jq`, never a here-string: bash fills a
# here-string's pipe itself, so a payload at or above the 64 KiB pipe capacity
# blocks the shell before jq runs, and the hook times out. CRs are stripped by
# parameter expansion rather than a `tr` stage.
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
COMMAND="${COMMAND//$'\r'/}"
[[ -n "$COMMAND" ]] || exit 0
[[ "$COMMAND" =~ (^|[^[:alnum:]_.-])[Gg][Ii][Tt][^[:alnum:]_-] ]] || exit 0
[[ "$COMMAND" == *worktree* ]] || exit 0
[[ "$COMMAND" == *add* ]] || exit 0

# One read per field, not hook::jq_fields: the batched reader's `// ""` and
# `tostring` differ from `// empty` on a non-string field.
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
  # The group holds only the helper, so the redirect silences its stderr alone
  # and `$?` is still its status. Read it here: inside `if ! cmd` it is always 0.
  { bash "$CLAIM" "${args[@]}" >/dev/null; } 2>/dev/null || claim_rc=$?
  [[ "$claim_rc" -eq 4 ]] && foreign+="${foreign:+, }$target"
done

if [[ -n "$foreign" ]]; then
  hook::emit_channels PostToolUse "source-control: $foreign already carries another session's live claim; it was not claimed for this session." ""
fi

exit 0
