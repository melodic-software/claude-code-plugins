#!/usr/bin/env bash
# worktree-claim.sh — claim check for linked worktrees (#2882).
#
# worktree-create.sh already arms `git worktree lock` on the trees it creates.
# A plain `git worktree add` does not, so concurrent sessions can reach into
# those trees with no claim to read. This script is the route that notices and
# (when asked) locks non-helper worktrees, and the gate a session runs before
# writing in one.
#
# git worktree lock prevents remove/move/prune. It does NOT block concurrent
# writes. The value of the reason string is as a claim other agents can read
# (git-worktree(1) "lock" / "LIST OUTPUT FORMAT" porcelain `locked [reason]`).
#
# Verbs:
#   report [--repo-dir DIR]
#     List each linked worktree as CLAIMED <path> <reason> or UNCLAIMED <path>.
#     Exit 1 when any linked worktree lacks a lock reason; 0 when every linked
#     worktree carries one (or none exist).
#   claim <path> [--repo-dir DIR] [--session-id ID]
#     Lock this unlocked linked worktree with a session-distinct reason.
#     Refuses to rewrite an existing reason (helper-created trees keep theirs).
#   claim --all-unclaimed [--repo-dir DIR] [--session-id ID]
#     Lock every currently unlocked linked worktree. An explicit repair
#     verb — the PostToolUse hook claims only the parsed add target so
#     two concurrent adds cannot steal each other's trees.
#   check-enter <path> [--repo-dir DIR] [--session-id ID]
#     Before writing: surface a foreign live claim and stop; report unclaimed;
#     allow only when the reason names this session.
#
# Exit codes:
#   0  report: no unclaimed linked worktrees
#      claim: locked, or already claimed by this session
#      check-enter: our claim, or path is not a linked worktree
#   1  report: one or more linked worktrees have no lock reason
#   2  usage
#   3  check-enter: the worktree is unclaimed (no lock reason)
#   4  check-enter: foreign live claim (reason printed)
#      claim: path already has a reason that is not this session's
#   5  environment: not a git repository, or path is not a registered worktree
#
# Session identity (claim / check-enter):
#   1. --session-id
#   2. CLAUDE_SESSION_ID when set and not the unexpanded `${CLAUDE_SESSION_ID}`
#      token
#   3. claim only: a generated host+pid+random token so two concurrent
#      invocations on one host still produce different reasons
#   check-enter without a session id cannot prove ownership: any lock reason
#   is treated as foreign.
set -uo pipefail

PROG=${0##*/}

EX_OK=0
EX_UNCLAIMED_REPORT=1
EX_USAGE=2
EX_UNCLAIMED=3
EX_FOREIGN=4
EX_ENV=5

usage() {
  cat >&2 <<EOF
Usage:
  $PROG report [--repo-dir DIR]
  $PROG claim <path> [--repo-dir DIR] [--session-id ID]
  $PROG claim --all-unclaimed [--repo-dir DIR] [--session-id ID]
  $PROG check-enter <path> [--repo-dir DIR] [--session-id ID]
EOF
  exit "$EX_USAGE"
}

git_unlocated() {
  (
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_CEILING_DIRECTORIES \
      GIT_DISCOVERY_ACROSS_FILESYSTEM GIT_INDEX_FILE GIT_PREFIX \
      GIT_OBJECT_DIRECTORY GIT_CONFIG
    git "$@"
  )
}

# Lexical collapse of `.` / `..` / `//`, plus trailing-slash trim. Pure
# string work so a not-yet-existing path still compares to porcelain.
normalize_path() {
  local input="$1" root rest seg
  input="${input%$'\r'}"
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
  local joined="${out[*]}"
  if [[ -n "$root" ]]; then
    printf '%s%s' "$root" "$joined"
  elif [[ -n "$joined" ]]; then
    printf '%s' "$joined"
  else
    printf '.'
  fi
}

# Make <path> absolute against <base> (default PWD), collapse `.`/`..`,
# and when the path exists resolve symlinks via `pwd -P` so a relative
# `check-enter .` or a `/tmp` vs `/private/tmp` spelling still matches
# porcelain (git-worktree(1) accepts relative or absolute).
canonicalize_path() {
  local p="$1" base="${2:-$PWD}" phys
  p="${p%$'\r'}"
  # shellcheck disable=SC2088
  if [[ "$p" == "~/"* && -n "${HOME:-}" ]]; then
    p="${HOME}/${p#\~/}"
  fi
  if [[ "$p" != /* && ! "$p" =~ ^[A-Za-z]:/ ]]; then
    p="${base%/}/$p"
  fi
  p="$(normalize_path "$p")"
  if [[ -d "$p" ]]; then
    phys="$(cd "$p" && pwd -P 2>/dev/null)" || phys=""
    [[ -n "$phys" ]] && p="$phys"
  elif [[ -e "$p" ]]; then
    local dir
    dir="$(cd "$(dirname -- "$p")" && pwd -P 2>/dev/null)" || dir=""
    if [[ -n "$dir" ]]; then
      p="${dir}/$(basename -- "$p")"
    fi
  fi
  printf '%s' "$p"
}

# Resolve --session-id / CLAUDE_SESSION_ID. Echoes empty when neither is usable.
resolve_session_id() {
  local sid="${1:-}"
  if [[ -n "$sid" ]]; then
    printf '%s' "$sid"
    return 0
  fi
  sid="${CLAUDE_SESSION_ID:-}"
  # SC2016: the unexpanded token is what we must reject.
  # shellcheck disable=SC2016
  if [[ -z "$sid" || "$sid" == '${CLAUDE_SESSION_ID}' ]]; then
    return 0
  fi
  printf '%s' "$sid"
}

# Reject a session id that would break the reason-string match or the lock
# file. Empty is allowed here (caller decides whether to generate).
valid_session_id() {
  [[ "$1" =~ ^[A-Za-z0-9._:-]{1,128}$ ]]
}

# New lock reason for a non-helper worktree. Session id is required so two
# concurrent sessions on one host produce different reasons. The helper's
# reason string is a different prefix (`worktree-create.sh:`) and is never
# written here — existing helper-created trees keep theirs (#2882 AC4).
claim_reason() {
  local sid="$1"
  local host="${HOSTNAME:-}"
  if [[ -z "$host" ]]; then
    host="$(hostname 2>/dev/null || printf 'unknown-host')"
  fi
  printf 'worktree-claim.sh: lane active on %s session %s since %s; unlock when the owning lane is done' \
    "$host" "$sid" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

# True when <reason> names <sid> as the owning session. Anchored on
# `session <sid> since` so `s1` does not match `s10`.
reason_is_ours() {
  local reason="$1" sid="$2"
  [[ -n "$sid" && "$reason" == *"session ${sid} since"* ]]
}

# Decode a porcelain `locked` value. Unquoted reasons are used as-is; quoted
# reasons (core.quotePath) drop the wrapping quotes and unescape \\ and \n.
decode_lock_reason() {
  local raw="$1"
  if [[ "$raw" == \"*\" ]]; then
    raw="${raw#\"}"
    raw="${raw%\"}"
    raw="${raw//\\n/$'\n'}"
    raw="${raw//\\\\/\\}"
  fi
  printf '%s' "$raw"
}

# parse_worktrees <repo>
# Fills WT_PATHS / WT_REASONS / WT_IS_LINKED (parallel arrays). Linked means
# "not the main worktree and not bare" — the main checkout being unlocked is
# normal and is not this check's subject.
parse_worktrees() {
  local repo="$1"
  WT_PATHS=()
  WT_REASONS=()
  WT_IS_LINKED=()
  local porcelain path="" reason="" bare=0 first=1 line
  porcelain="$(git_unlocated -C "$repo" worktree list --porcelain | tr -d '\r')" || return 1

  flush_record() {
    if [[ -n "$path" && "$bare" -eq 0 ]]; then
      # The first non-bare record git emits is the MAIN worktree; every later
      # one is linked.
      WT_PATHS+=("$path")
      WT_REASONS+=("$reason")
      WT_IS_LINKED+=("$((first ? 0 : 1))")
      first=0
    elif [[ "$bare" -eq 1 ]]; then
      first=0
    fi
    path=""
    reason=""
    bare=0
  }

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -z "$line" ]]; then
      flush_record
      continue
    fi
    case "$line" in
    worktree\ *)
      path="$(canonicalize_path "${line#worktree }")"
      ;;
    bare)
      bare=1
      ;;
    locked)
      reason=""
      ;;
    locked\ *)
      reason="$(decode_lock_reason "${line#locked }")"
      ;;
    *) ;;
    esac
  done <<<"$porcelain"
  flush_record
}

# Longest worktree-path prefix of <target>, or empty. <target> must already
# be canonicalized (absolute, `.`/`..` collapsed, symlinks resolved).
find_worktree_index() {
  local target="$1" i best=-1 best_len=0
  for i in "${!WT_PATHS[@]}"; do
    local wt="${WT_PATHS[i]}"
    if [[ "$target" == "$wt" || "$target" == "$wt"/* ]]; then
      if ((${#wt} > best_len)); then
        best="$i"
        best_len=${#wt}
      fi
    fi
  done
  if ((best >= 0)); then
    printf '%s' "$best"
    return 0
  fi
  return 1
}

resolve_repo_dir() {
  local hint="$1"
  if [[ -n "$hint" ]]; then
    if git_unlocated -C "$hint" rev-parse --git-dir >/dev/null 2>&1; then
      printf '%s' "$hint"
      return 0
    fi
    return 1
  fi
  if git_unlocated rev-parse --git-dir >/dev/null 2>&1; then
    printf '%s' "."
    return 0
  fi
  return 1
}

cmd="${1:-}"
[[ -n "$cmd" ]] || usage
shift

repo_dir=""
session_id=""
path=""
all_unclaimed=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  --repo-dir)
    [[ $# -ge 2 ]] || usage
    repo_dir="$2"
    shift 2
    ;;
  --session-id)
    [[ $# -ge 2 ]] || usage
    session_id="$2"
    shift 2
    ;;
  --all-unclaimed)
    all_unclaimed=1
    shift
    ;;
  -h | --help)
    usage
    ;;
  --)
    shift
    break
    ;;
  -*)
    printf '%s: unknown flag: %s\n' "$PROG" "$1" >&2
    usage
    ;;
  *)
    if [[ -n "$path" ]]; then
      printf '%s: unexpected argument: %s\n' "$PROG" "$1" >&2
      usage
    fi
    path="$1"
    shift
    ;;
  esac
done

session_id="$(resolve_session_id "$session_id")"
if [[ -n "$session_id" ]] && ! valid_session_id "$session_id"; then
  printf '%s: --session-id must match ^[A-Za-z0-9._:-]{1,128}$\n' "$PROG" >&2
  exit "$EX_USAGE"
fi

case "$cmd" in
report | claim | check-enter) ;;
*)
  printf '%s: unknown verb: %s\n' "$PROG" "$cmd" >&2
  usage
  ;;
esac

if [[ "$cmd" == "claim" ]]; then
  if ((all_unclaimed == 0)) && [[ -z "$path" ]]; then
    printf '%s: claim requires a path or --all-unclaimed\n' "$PROG" >&2
    exit "$EX_USAGE"
  fi
  if ((all_unclaimed == 1)) && [[ -n "$path" ]]; then
    printf '%s: claim: pass a path or --all-unclaimed, not both\n' "$PROG" >&2
    exit "$EX_USAGE"
  fi
fi
if [[ "$cmd" == "check-enter" && -z "$path" ]]; then
  printf '%s: check-enter requires a path\n' "$PROG" >&2
  exit "$EX_USAGE"
fi
if [[ "$cmd" == "report" && -n "$path" ]]; then
  printf '%s: report takes no path\n' "$PROG" >&2
  exit "$EX_USAGE"
fi

# Resolve relative / `.` / symlink spellings before matching porcelain.
# A `check-enter .` from inside a linked worktree must see that tree's claim.
if [[ -n "$path" ]]; then
  path="$(canonicalize_path "$path")"
fi
if [[ -n "$repo_dir" ]]; then
  repo_dir="$(canonicalize_path "$repo_dir")"
fi

# A path can locate the repository when --repo-dir was omitted.
repo_hint="$repo_dir"
if [[ -z "$repo_hint" && -n "$path" ]]; then
  repo_hint="$path"
fi
if ! repo_dir="$(resolve_repo_dir "$repo_hint")"; then
  printf '%s: not a git repository: %s\n' "$PROG" "${repo_hint:-$PWD}" >&2
  exit "$EX_ENV"
fi

if ! parse_worktrees "$repo_dir"; then
  printf '%s: could not list worktrees in %s\n' "$PROG" "$repo_dir" >&2
  exit "$EX_ENV"
fi

do_report() {
  local i unclaimed=0 linked=0
  for i in "${!WT_PATHS[@]}"; do
    ((WT_IS_LINKED[i])) || continue
    linked=$((linked + 1))
    if [[ -n "${WT_REASONS[i]}" ]]; then
      printf 'CLAIMED\t%s\t%s\n' "${WT_PATHS[i]}" "${WT_REASONS[i]}"
    else
      printf 'UNCLAIMED\t%s\n' "${WT_PATHS[i]}"
      unclaimed=$((unclaimed + 1))
    fi
  done
  printf '%s: %d linked, %d unclaimed, %d claimed\n' \
    "$PROG" "$linked" "$unclaimed" "$((linked - unclaimed))" >&2
  if ((unclaimed > 0)); then
    return "$EX_UNCLAIMED_REPORT"
  fi
  return "$EX_OK"
}

# Generate a session id only when claiming and the caller supplied none.
# Distinct per invocation so two concurrent claims on one host differ.
ensure_claim_session() {
  if [[ -n "$session_id" ]]; then
    return 0
  fi
  local host="${HOSTNAME:-unknown-host}" rand
  rand="$(date -u +%s%N 2>/dev/null || date -u +%s)"
  session_id="term-${host}-$$-${rand}"
  session_id="${session_id//[^A-Za-z0-9._:-]/-}"
  if ! valid_session_id "$session_id"; then
    session_id="term-$$"
  fi
}

lock_one() {
  local wt_path="$1" existing="$2"
  if [[ -n "$existing" ]]; then
    if reason_is_ours "$existing" "$session_id"; then
      printf '%s\n' "$existing"
      return "$EX_OK"
    fi
    printf '%s: already claimed: %s\n' "$PROG" "$existing" >&2
    return "$EX_FOREIGN"
  fi
  local reason
  reason="$(claim_reason "$session_id")"
  if ! git_unlocated -C "$repo_dir" worktree lock --reason "$reason" "$wt_path" >&2; then
    printf '%s: git worktree lock failed for %s\n' "$PROG" "$wt_path" >&2
    return "$EX_ENV"
  fi
  printf '%s\n' "$reason"
  return "$EX_OK"
}

do_claim_one() {
  local idx
  if ! idx="$(find_worktree_index "$path")"; then
    printf '%s: not a registered worktree: %s\n' "$PROG" "$path" >&2
    exit "$EX_ENV"
  fi
  if ((WT_IS_LINKED[idx] == 0)); then
    printf '%s: refusing to claim the main worktree: %s\n' "$PROG" "${WT_PATHS[idx]}" >&2
    exit "$EX_USAGE"
  fi
  ensure_claim_session
  lock_one "${WT_PATHS[idx]}" "${WT_REASONS[idx]}"
}

do_claim_all() {
  local i rc=0 any=0 st
  ensure_claim_session
  for i in "${!WT_PATHS[@]}"; do
    ((WT_IS_LINKED[i])) || continue
    [[ -z "${WT_REASONS[i]}" ]] || continue
    any=1
    # Capture lock_one's status directly. `if ! lock_one; then rc=$?` is
    # always 0: the `!` makes the if-body run on failure, and `$?` then
    # reflects the successful test, not lock_one (#2882 review).
    lock_one "${WT_PATHS[i]}" ""
    st=$?
    if ((st != 0)); then
      rc=$st
    fi
  done
  if ((any == 0)); then
    printf '%s: no unclaimed linked worktrees\n' "$PROG" >&2
  fi
  return "$rc"
}

do_check_enter() {
  local idx
  if ! idx="$(find_worktree_index "$path")"; then
    # Not a linked (or main) worktree path — nothing to consult.
    return "$EX_OK"
  fi
  if ((WT_IS_LINKED[idx] == 0)); then
    return "$EX_OK"
  fi
  local wt="${WT_PATHS[idx]}"
  local reason="${WT_REASONS[idx]}"
  if [[ -z "$reason" ]]; then
    printf 'UNCLAIMED: %s carries no lock reason\n' "$wt" >&2
    printf '  claim it first: %s claim %s --session-id <session-id>\n' "$PROG" "$wt" >&2
    return "$EX_UNCLAIMED"
  fi
  if reason_is_ours "$reason" "$session_id"; then
    printf 'CLAIMED: %s\n' "$reason"
    return "$EX_OK"
  fi
  printf 'FOREIGN CLAIM: %s\n' "$reason" >&2
  printf '  path: %s\n' "$wt" >&2
  printf '  stop: another session holds a live claim on this worktree; do not write here\n' >&2
  return "$EX_FOREIGN"
}

case "$cmd" in
report)
  do_report
  exit $?
  ;;
claim)
  if ((all_unclaimed)); then
    do_claim_all
    exit $?
  fi
  do_claim_one
  exit $?
  ;;
check-enter)
  do_check_enter
  exit $?
  ;;
*)
  printf '%s: unknown verb: %s\n' "$PROG" "$cmd" >&2
  usage
  ;;
esac
