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
INPUT=$(hook::buffer_stdin) || exit 0

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

# Set once a segment changes the working directory; every later segment then
# resolves against a directory this hook cannot see (same rule as the
# containment sibling).
DIR_CHANGED=0
CLAIM_TARGETS=()

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
is_dynamic() {
  [[ "$1" == *'$'* || "$1" == *'`'* ]]
}

# shellcheck disable=SC2329
is_abs_path() {
  [[ "$1" == /* || "$1" =~ ^[A-Za-z]:[/\\] ]]
}

# shellcheck disable=SC2329
normalize_path() {
  local input="$1" root rest seg
  if [[ "$input" == /* ]]; then
    root="/"
    rest="${input#/}"
  elif [[ "$input" =~ ^[A-Za-z]:/ ]]; then
    root="${input:0:2}/"
    rest="${input:3}"
  else
    root=""
    rest="$input"
  fi
  local -a segs=() out=()
  IFS='/' read -r -a segs <<<"$rest"
  for seg in "${segs[@]}"; do
    [[ -z "$seg" || "$seg" == "." ]] && continue
    if [[ "$seg" == ".." ]]; then
      ((${#out[@]})) && out=("${out[@]:0:${#out[@]}-1}")
      continue
    fi
    out+=("$seg")
  done
  local IFS='/'
  printf '%s%s' "$root" "${out[*]}"
}

# shellcheck disable=SC2329
resolve_against() {
  local base="$1" p="$2"
  if [[ ("$p" == *\\* || "$base" == *\\*) && ("${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin*) ]]; then
    local bslash="\\" fwd="/"
    p="${p//"$bslash"/"$fwd"}"
    base="${base//"$bslash"/"$fwd"}"
  fi
  # shellcheck disable=SC2088
  if [[ "$p" == "~/"* && -n "${HOME:-}" ]]; then
    p="${HOME}/${p#\~/}"
  fi
  # shellcheck disable=SC2310
  if is_abs_path "$p"; then
    printf '%s' "$p"
    return 0
  fi
  [[ -n "$base" ]] || return 0
  printf '%s/%s' "${base%/}" "$p"
}

# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
collect_add() {
  local -a w=("$@")
  local n=$# i=0 d word

  if hook::shell_c_operand "$@"; then
    hook::bash_parse_segments "$HOOK_SHELL_C_OPERAND" collect_add
    return 0
  fi

  while ((i < n)) && [[ "${w[i]}" == *=* && "${w[i]}" != -* ]]; do ((i++)); done

  d=$i
  while ((d < n)); do
    case "${w[d]}" in
    command | builtin | eval | -p) ((d++)) ;;
    *) break ;;
    esac
  done
  case "${w[d]:-}" in
  cd | pushd | popd)
    DIR_CHANGED=1
    return 0
    ;;
  *) ;;
  esac
  ((DIR_CHANGED)) && return 0

  hook::git_resolve_index "${w[@]}" || return 0
  local gi="$HOOK_GIT_RESOLVED_GI"
  local -a words=("${HOOK_GIT_RESOLVED_WORDS[@]}")
  local -a wrapper_dirs=()
  ((${#HOOK_GIT_RESOLVED_WRAPPER_DIRS[@]})) && wrapper_dirs=("${HOOK_GIT_RESOLVED_WRAPPER_DIRS[@]}")
  n=${#words[@]}

  hook::git_resolve_subcommand "$gi" "${words[@]}" || return 0
  [[ "$HOOK_GIT_SUB" == "worktree" ]] || return 0
  local sub_idx="$HOOK_GIT_SUB_IDX"
  [[ "${words[sub_idx + 1]:-}" == "add" ]] || return 0

  local base="$HOOK_CWD" hop
  for hop in ${wrapper_dirs[@]+"${wrapper_dirs[@]}"}; do
    # shellcheck disable=SC2310
    is_dynamic "$hop" && return 0
    base=$(resolve_against "$base" "$hop")
    [[ -n "$base" ]] || return 0
  done
  local j=$((gi + 1))
  while ((j < sub_idx)); do
    if [[ "${words[j]}" == "-C" ]]; then
      hop="${words[j + 1]:-}"
      [[ -n "$hop" ]] || return 0
      # shellcheck disable=SC2310
      is_dynamic "$hop" && return 0
      base=$(resolve_against "$base" "$hop")
      [[ -n "$base" ]] || return 0
      ((j += 2))
      continue
    fi
    ((j++))
  done

  local target="" seen_ddash=0
  for ((j = sub_idx + 2; j < n; j++)); do
    word="${words[j]}"
    if ((seen_ddash == 0)); then
      case "$word" in
      --)
        seen_ddash=1
        continue
        ;;
      -b | -B | --reason)
        ((j++))
        continue
        ;;
      -*)
        continue
        ;;
      *) ;;
      esac
    fi
    target="$word"
    break
  done
  [[ -n "$target" ]] || return 0
  # shellcheck disable=SC2310
  is_dynamic "$target" && return 0

  local abs
  abs=$(resolve_against "$base" "$target")
  [[ -n "$abs" ]] || return 0
  abs=$(normalize_path "$abs")
  CLAIM_TARGETS+=("$abs")
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
