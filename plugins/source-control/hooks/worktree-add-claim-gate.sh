#!/usr/bin/env bash
# worktree-add-claim-gate.sh — PostToolUse hook: after a raw Bash
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
# worktree_add_claim_gate_enabled.
#
# The lock is a *claim other agents can read*. It does not block concurrent
# writes — git-worktree(1) lock only prevents remove/move/prune.

set -uo pipefail

# Kill switch FIRST, before any library is sourced: a disabled hook must not
# pay to parse hook-utils.sh to learn it is off. Same predicate as
# hook::is_enabled; scripts/check-killswitch-hoist.sh pins the two together.
[[ "${CLAUDE_PLUGIN_OPTION_WORKTREE_ADD_CLAIM_GATE_ENABLED:-true}" == "true" ]] || exit 0
# Hook directory by parameter expansion, never `dirname`. GNU Bash forks a
# subshell for every command substitution even when the body is a builtin
# (Command Substitution, Bash Reference Manual). On Windows Git Bash that
# fork is a process. `${BASH_SOURCE[0]%/*}` equals dirname for every shape
# BASH_SOURCE takes; the fallback covers a bare filename, where the strip is a
# no-op and dirname answers `.`.
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
# shellcheck source=worktree-path-lib.sh
source "$HOOK_DIR/worktree-path-lib.sh"
hook::buffer_stdin_to INPUT || exit 0

hook::require_jq "PostToolUse" "source-control-worktree-add-claim-gate" "$INPUT"

# ONE `jq` for the field and no `tr` behind it. The payload is fed through
# `printf '%s' "$INPUT" | jq`, the form lib/hook-utils.sh prescribes for a hook
# payload (hook::jq_field, hook::json_complete) and NEVER a here-string: bash
# fills a here-string's pipe itself, so a payload at or above the pipe capacity
# (65536 bytes, traced on Git Bash in #1587) blocks the shell before jq is ever
# exec'd, and that hang is this hook's timeout. The separate writer process is
# the correct trade: 3 creations for the read where a here-string costs 1. The
# CR strip is the same all-CRs-removed contract done with parameter expansion
# instead of a `| tr -d '\r'` stage. Same form as the containment sibling;
# strace counted 4 creations / 2 execve before, 3 / 1 after.
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
COMMAND="${COMMAND//$'\r'/}"
[[ -n "$COMMAND" ]] || exit 0
[[ "$COMMAND" =~ (^|[^[:alnum:]_.-])[Gg][Ii][Tt][^[:alnum:]_-] ]] || exit 0
[[ "$COMMAND" == *worktree* ]] || exit 0
[[ "$COMMAND" == *add* ]] || exit 0

# Same `printf | jq` feed as the command read above. Two reads rather than one
# hook::jq_fields call for both: the batched reader's `// ""` and `tostring`
# semantics differ from `// empty` on a non-string field, and its NUL-flag
# verdict contract is one a blocking-adjacent caller would then have to honour.
# Keeping each field's own `// empty` read is what keeps this behaviour-preserving.
HOOK_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
HOOK_CWD="${HOOK_CWD//$'\r'/}"
SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
SESSION="${SESSION//$'\r'/}"

CLAIM="$HOOK_DIR/../scripts/worktree-claim.sh"
[[ -f "$CLAIM" ]] || exit 0

CLAIM_TARGETS=()

# The parse, the `cd`/`pushd`/`popd` poisoning, the wrapper/`-C` base
# composition and the add-target walk are worktree-path-lib.sh's, shared
# verbatim with the containment sibling so the two gates can never disagree
# about which target an executed command named. Only the claim is this hook's.
# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
collect_add() {
  local abs
  # shellcheck disable=SC2310  # the return status IS the verdict; abs is read only on 0
  if worktree_add_target_to abs collect_add "$HOOK_CWD" "$@"; then
    CLAIM_TARGETS+=("$abs")
  fi
  return 0
}

hook::bash_parse_segments "$COMMAND" collect_add

# Nothing we could honestly attribute to an executed `git worktree add`.
((${#CLAIM_TARGETS[@]})) || exit 0

claimed_any=0
foreign_any=0

for target in "${CLAIM_TARGETS[@]}"; do
  args=(claim "$target")
  if [[ -n "$SESSION" ]]; then
    args+=(--session-id "$SESSION")
  fi
  claim_rc=0
  # The helper's stderr is discarded, and `2>/dev/null` is the whole of what the
  # temp file used to do: it was created, written by the redirection, and
  # removed without ever being read. Dropping it removes two processes (mktemp,
  # rm) and the `|| continue` fail-open that silently skipped the claim whenever
  # TMPDIR was unwritable. The redirection sits on a group holding exactly ONE
  # command, so it silences the helper's stderr and nothing else, and `$?` on
  # the group is still the HELPER's status — `claim_rc=$?` stays outside it, per
  # the reason spelled out in the create-gate sibling: read inside `if ! cmd`
  # it would be a constant 0.
  { claim_out="$(bash "$CLAIM" "${args[@]}")"; } 2>/dev/null || claim_rc=$?
  if [[ "$claim_out" == *"worktree-claim.sh: lane active"* && "$claim_rc" -eq 0 ]]; then
    claimed_any=1
  fi
  if [[ "$claim_rc" -eq 4 ]]; then
    foreign_any=1
  fi
done

ctx=""
if ((claimed_any)); then
  ctx="source-control: claimed unlocked worktree after git worktree add (session ${SESSION:-unknown}). Before writing in a worktree, run worktree-claim.sh check-enter <path> --session-id <id>. A foreign live claim is a stop."
fi
if ((foreign_any)); then
  if [[ -n "$ctx" ]]; then
    ctx="${ctx} A sibling target already carries a live claim (not rewritten)."
  else
    ctx="source-control: a linked worktree already carries a live claim; not rewriting it."
  fi
fi
if [[ -n "$ctx" ]]; then
  hook::emit_channels PostToolUse "$ctx" ""
fi

exit 0
