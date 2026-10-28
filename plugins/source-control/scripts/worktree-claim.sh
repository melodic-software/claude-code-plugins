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
#   report [--repo-dir DIR] [--root DIR]
#     List each linked worktree as CLAIMED <path> <reason> or UNCLAIMED <path>.
#     Exit 1 when any linked worktree lacks a lock reason; 0 when every linked
#     worktree carries one (or none exist). With --root, a further summary line
#     counts the UNCLAIMED worktrees that lie outside that worktree root.
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
#   release <path> [--repo-dir DIR] [--session-id ID]
#     Inverse of claim: unlock a linked worktree whose reason names this
#     session. An unlocked tree is a no-op; a foreign or reasonless lock is
#     never removed (reason printed).
#   stale <path> [--repo-dir DIR] [--idle-minutes N]
#     Read-only. Exit 0 only when the lock is provably stale: a linked worktree
#     whose reason reads `lane active on <host> session <sid> since`, <host> is
#     this host, and no ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/*/<sid>.jsonl
#     changed within N minutes (default 120; a missing transcript is idle). It
#     does not look at PR or landed state; the caller requires that separately.
#   stale --batch --repo-dir DIR [--idle-minutes N]
#     The same verdict for each NUL-delimited path on stdin, from one worktree
#     list parse and one transcript scan. Prints one `exit<TAB>path<TAB>note`
#     row per path, in input order, where exit and note are what single-path
#     `stale` would return and print for it (a tab or newline in the note reads
#     as a space). A path holding a tab or newline is usage (exit 2) and no row
#     is printed. --repo-dir is required: no single path locates the repository.
#
# Requires git >= 2.36.0 (`git worktree list --porcelain -z`); older git fails
# closed with exit 5 and a message naming the floor and the installed version.
#
# Exit codes:
#   0  report: no unclaimed linked worktrees
#      stale: provably stale (one evidence line printed)
#      stale --batch: every path evaluated (each row carries its own exit)
#      claim: locked, or already claimed by this session
#      check-enter: our claim, or path is not a linked worktree
#      release: unlocked this session's lock, or the tree was already unlocked
#   1  report: one or more linked worktrees have no lock reason
#      stale: not provably stale (unlocked, reasonless, no session, another
#      host, or a transcript changed within the idle window)
#   2  usage (release: main worktree, or no session id to prove ownership)
#   3  check-enter: the worktree is unclaimed (no lock reason)
#   4  check-enter: foreign live claim (reason printed)
#      claim: path already has a reason that is not this session's
#      release: the lock is foreign or carries no session (reason printed)
#   5  environment: not a git repository, or path is not a registered worktree
#
# Session identity (claim / check-enter / release):
#   1. --session-id
#   2. CLAUDE_SESSION_ID when set and not the unexpanded `${CLAUDE_SESSION_ID}`
#      token
#   3. claim only: a generated host+pid+random token so two concurrent
#      invocations on one host still produce different reasons
#   check-enter without a session id cannot prove ownership: any lock reason
#   is treated as foreign. release without one exits 2.
set -uo pipefail

PROG=${0##*/}

# Lexical path collapse, shared inside this plugin with the worktree gates and
# the creation helper. Sourced for worktree_path_normalize alone: the file
# defines functions only and pulls in no library of its own.
SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
[[ "$SCRIPT_DIR" == "${BASH_SOURCE[0]}" ]] && SCRIPT_DIR=.
# shellcheck source=../hooks/worktree-path-lib.sh
source "$SCRIPT_DIR/../hooks/worktree-path-lib.sh"

EX_OK=0
EX_UNCLAIMED_REPORT=1
EX_USAGE=2
EX_UNCLAIMED=3
EX_FOREIGN=4
EX_ENV=5

usage() {
  cat >&2 <<EOF
Usage:
  $PROG report [--repo-dir DIR] [--root DIR]
  $PROG claim <path> [--repo-dir DIR] [--session-id ID]
  $PROG claim --all-unclaimed [--repo-dir DIR] [--session-id ID]
  $PROG check-enter <path> [--repo-dir DIR] [--session-id ID]
  $PROG release <path> [--repo-dir DIR] [--session-id ID]
  $PROG stale <path> [--repo-dir DIR] [--idle-minutes N]
  $PROG stale --batch --repo-dir DIR [--idle-minutes N] < NUL-delimited paths
EOF
  exit "$EX_USAGE"
}

# shellcheck source=lib/worktree-facts.sh
source "$SCRIPT_DIR/lib/worktree-facts.sh" || { echo "error: cannot load lib/worktree-facts.sh" >&2; exit "$EX_ENV"; }

git_unlocated() {
  (
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_CEILING_DIRECTORIES \
      GIT_DISCOVERY_ACROSS_FILESYSTEM GIT_INDEX_FILE GIT_PREFIX \
      GIT_OBJECT_DIRECTORY GIT_CONFIG
    git "$@"
  )
}

# Lexical collapse of `.` / `..` / `//`, plus trailing-slash trim. Pure
# string work so a not-yet-existing path still compares to porcelain. The
# collapse itself is worktree-path-lib.sh's, shared with the worktree gates and
# the creation helper; this script's own two additions stay here: a trailing CR
# is dropped (git porcelain read on an MSYS/Cygwin shell carries CRLF), and a
# relative path that collapses away answers `.` rather than the empty string.
normalize_path() {
  local collapsed
  collapsed=$(worktree_path_normalize "${1%$'\r'}")
  printf '%s' "${collapsed:-.}"
}

# Make <path> absolute against <base> (default PWD), collapse `.`/`..`,
# and when the path exists resolve symlinks via `pwd -P` so a relative
# `check-enter .` or a `/tmp` vs `/private/tmp` spelling still matches
# porcelain (git-worktree(1) accepts relative or absolute).
canonicalize_path() {
  local out
  canonicalize_path_to out "$@"
  printf '%s' "$out"
}

# canonicalize_path_to <var> <path> [base]: canonicalize_path into <var>
# without forking in the common case (an already-clean path to an existing
# directory), which parse_worktrees hits once per registered worktree. Siblings
# under one non-symlink parent share a single `cd -P` through CANON_PARENT.
CANON_PARENT=""
CANON_PARENT_PHYS=""
canonicalize_path_to() {
  local __var="$1" p="$2" base="${3:-$PWD}" here="$PWD" phys
  p="${p%$'\r'}"
  # shellcheck disable=SC2088
  if [[ "$p" == "~/"* && -n "${HOME:-}" ]]; then
    p="${HOME}/${p#\~/}"
  fi
  if [[ "$p" != /* && ! "$p" =~ ^[A-Za-z]:/ ]]; then
    p="${base%/}/$p"
  fi
  if [[ "$p" == *//* || "$p" == */./* || "$p" == */../* || "$p" == */. || "$p" == */.. || "$p" == ?*/ ]]; then
    p="$(normalize_path "$p")"
  fi
  local parent="${p%/*}"
  if [[ -d "$p" && ! -L "$p" && -n "$parent" && "$parent" == "$CANON_PARENT" ]]; then
    # Sibling of the last directory resolved: reuse its parent's physical path.
    p="${CANON_PARENT_PHYS}/${p##*/}"
  elif [[ -d "$p" && -d "$here" ]] && CDPATH='' builtin cd -P -- "$p" 2>/dev/null; then
    phys="$PWD"
    builtin cd -- "$here" || exit "$EX_ENV"
    if [[ ! -L "$p" && -n "$parent" ]]; then
      CANON_PARENT="$parent"
      CANON_PARENT_PHYS="${phys%/*}"
    fi
    p="$phys"
  elif [[ -d "$p" ]]; then
    phys="$(cd "$p" && pwd -P 2>/dev/null)" || phys=""
    [[ -n "$phys" ]] && p="$phys"
  elif [[ -e "$p" ]]; then
    local dir
    dir="$(cd "$(dirname -- "$p")" && pwd -P 2>/dev/null)" || dir=""
    if [[ -n "$dir" ]]; then
      p="${dir}/$(basename -- "$p")"
    fi
  fi
  printf -v "$__var" '%s' "$p"
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

# parse_worktrees <repo>
# Fills WT_PATHS / WT_REASONS / WT_IS_LINKED from the shared fact record.
# Linked means "not the main worktree and not bare".
parse_worktrees() {
  local repo="$1" porcelain i canon
  WT_PATHS=()
  WT_REASONS=()
  WT_IS_LINKED=()
  porcelain="$(mktemp)" || return 1
  if ! git_unlocated -C "$repo" worktree list --porcelain -z >"$porcelain"; then
    rm -f "$porcelain"
    return 1
  fi
  worktree_facts_parse_z "$porcelain"
  rm -f "$porcelain"
  [[ ${#WT_FACT_PATH[@]} -gt 0 ]] || return 0
  for i in "${!WT_FACT_PATH[@]}"; do
    [[ "${WT_FACT_BARE[$i]}" == "yes" ]] && continue
    canonicalize_path_to canon "${WT_FACT_PATH[$i]}"
    WT_PATHS+=("$canon")
    WT_REASONS+=("${WT_FACT_LOCKED[$i]}")
    if [[ "${WT_FACT_LINKED[$i]}" == "yes" ]]; then
      WT_IS_LINKED+=(1)
    else
      WT_IS_LINKED+=(0)
    fi
  done
}

# Index of the longest worktree-path prefix of <target> into WT_INDEX; fails
# when none matches. <target> must already be canonicalized (absolute, `.`/`..`
# collapsed, symlinks resolved). Set, not printed, so a caller needs no subshell.
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
  WT_INDEX="$best"
  ((best >= 0))
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
batch=0
idle_minutes=120
root_dir=""

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
  --root)
    [[ $# -ge 2 ]] || usage
    root_dir="$2"
    shift 2
    ;;
  --idle-minutes)
    [[ $# -ge 2 ]] || usage
    idle_minutes="$2"
    shift 2
    ;;
  --all-unclaimed)
    all_unclaimed=1
    shift
    ;;
  --batch)
    batch=1
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
report | claim | check-enter | release | stale) ;;
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
if [[ "$cmd" == "release" && -z "$path" ]]; then
  printf '%s: release requires a path\n' "$PROG" >&2
  exit "$EX_USAGE"
fi
if [[ "$cmd" == "release" && -z "$session_id" ]]; then
  printf '%s: release needs --session-id or CLAUDE_SESSION_ID to prove ownership\n' "$PROG" >&2
  exit "$EX_USAGE"
fi
if ((batch)) && [[ "$cmd" != "stale" ]]; then
  printf '%s: --batch applies to stale only\n' "$PROG" >&2
  exit "$EX_USAGE"
fi
if ((batch)) && [[ -n "$path" ]]; then
  printf '%s: stale --batch reads its paths from stdin, not arguments\n' "$PROG" >&2
  exit "$EX_USAGE"
fi
if ((batch)) && [[ -z "$repo_dir" ]]; then
  printf '%s: stale --batch needs --repo-dir\n' "$PROG" >&2
  exit "$EX_USAGE"
fi
if [[ "$cmd" == "stale" ]] && ((batch == 0)) && [[ -z "$path" ]]; then
  printf '%s: stale requires a path\n' "$PROG" >&2
  exit "$EX_USAGE"
fi
if [[ ! "$idle_minutes" =~ ^[0-9]{1,9}$ ]]; then
  printf '%s: --idle-minutes must be a non-negative integer\n' "$PROG" >&2
  exit "$EX_USAGE"
fi
if [[ -n "$root_dir" && "$cmd" != "report" ]]; then
  printf '%s: --root applies to report only\n' "$PROG" >&2
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
  printf '%s: could not list worktrees in %s (%s)\n' "$PROG" "$repo_dir" "$(worktree_list_z_floor_note)" >&2
  exit "$EX_ENV"
fi

do_report() {
  local i unclaimed=0 linked=0 outside=0 root=""
  [[ -z "$root_dir" ]] || root="$(canonicalize_path "$root_dir")"
  for i in "${!WT_PATHS[@]}"; do
    ((WT_IS_LINKED[i])) || continue
    linked=$((linked + 1))
    if [[ -n "${WT_REASONS[i]}" ]]; then
      printf 'CLAIMED\t%s\t%s\n' "${WT_PATHS[i]}" "${WT_REASONS[i]}"
    else
      printf 'UNCLAIMED\t%s\n' "${WT_PATHS[i]}"
      unclaimed=$((unclaimed + 1))
      if [[ -n "$root" && "${WT_PATHS[i]}" != "$root"/* ]]; then
        outside=$((outside + 1))
      fi
    fi
  done
  printf '%s: %d linked, %d unclaimed, %d claimed\n' \
    "$PROG" "$linked" "$unclaimed" "$((linked - unclaimed))" >&2
  if [[ -n "$root" ]]; then
    printf '%s: %d unclaimed outside the worktree root %s\n' "$PROG" "$outside" "$root" >&2
  fi
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
    if worktree_reason_is_ours "$existing" "$session_id"; then
      printf '%s\n' "$existing"
      return "$EX_OK"
    fi
    printf '%s: already claimed: %s\n' "$PROG" "$existing" >&2
    return "$EX_FOREIGN"
  fi
  local reason
  reason="$(worktree_lock_reason worktree-claim.sh "$session_id")"
  if ! git_unlocated -C "$repo_dir" worktree lock --reason "$reason" "$wt_path" >&2; then
    printf '%s: git worktree lock failed for %s\n' "$PROG" "$wt_path" >&2
    return "$EX_ENV"
  fi
  printf '%s\n' "$reason"
  return "$EX_OK"
}

do_claim_one() {
  local idx
  if ! find_worktree_index "$path"; then
    printf '%s: not a registered worktree: %s\n' "$PROG" "$path" >&2
    exit "$EX_ENV"
  fi
  idx="$WT_INDEX"
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
  if ! find_worktree_index "$path"; then
    # Not a linked (or main) worktree path — nothing to consult.
    return "$EX_OK"
  fi
  idx="$WT_INDEX"
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
  if worktree_reason_is_ours "$reason" "$session_id"; then
    printf 'CLAIMED: %s\n' "$reason"
    return "$EX_OK"
  fi
  printf 'FOREIGN CLAIM: %s\n' "$reason" >&2
  printf '  path: %s\n' "$wt" >&2
  printf '  stop: another session holds a live claim on this worktree; do not write here\n' >&2
  return "$EX_FOREIGN"
}

do_release() {
  local idx wt reason
  if ! find_worktree_index "$path"; then
    printf '%s: not a registered worktree: %s\n' "$PROG" "$path" >&2
    return "$EX_ENV"
  fi
  idx="$WT_INDEX"
  wt="${WT_PATHS[idx]}"
  if ((WT_IS_LINKED[idx] == 0)); then
    printf '%s: refusing to release the main worktree: %s\n' "$PROG" "$wt" >&2
    return "$EX_USAGE"
  fi
  reason="${WT_REASONS[idx]}"
  if [[ -z "$reason" ]]; then
    printf '%s: not locked: %s\n' "$PROG" "$wt" >&2
    return "$EX_OK"
  fi
  if ! worktree_reason_is_ours "$reason" "$session_id"; then
    printf '%s: not released, the lock is not this session'\''s: %s\n' "$PROG" "$reason" >&2
    return "$EX_FOREIGN"
  fi
  if ! git_unlocated -C "$repo_dir" worktree unlock "$wt" >&2; then
    printf '%s: git worktree unlock failed for %s\n' "$PROG" "$wt" >&2
    return "$EX_ENV"
  fi
  printf 'released %s\n' "$wt"
}

# scan_transcripts <name> [-quit]: on its first call only, list each
# <projects>/*/<name> changed within the idle window into TRANSCRIPTS, one per
# line with a newline on each side, so a session's lookup is one string match.
# A batch passes `*.jsonl` to cover every session at once; a single path passes
# its own <sid>.jsonl and -quit. TRANSCRIPT_SCAN records ok, unreadable or failed.
TRANSCRIPT_SCAN=""
TRANSCRIPTS=""
scan_transcripts() {
  [[ -z "$TRANSCRIPT_SCAN" ]] || return 0
  local found
  TRANSCRIPT_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
  if [[ ! -d "$TRANSCRIPT_DIR" || ! -r "$TRANSCRIPT_DIR" ]]; then
    TRANSCRIPT_SCAN=unreadable
  elif found="$(find "$TRANSCRIPT_DIR" -mindepth 2 -maxdepth 2 -name "$1" -mmin "-$idle_minutes" -print ${2:+"$2"} 2>/dev/null)"; then
    TRANSCRIPT_SCAN=ok
    TRANSCRIPTS=$'\n'"$found"$'\n'
  else
    TRANSCRIPT_SCAN=failed
  fi
}

# stale_verdict <canonical-path>: the stale verdict into STALE_NOTE, returned as
# the exit code `stale` documents. Forks only for the host name and the
# transcript scan, each once per run, so --batch pays nothing more per path.
# ponytail: liveness is provable only from this host's transcripts; a lock from
# another host, or without a session id, stays "not provable".
THIS_HOST=""
stale_verdict() {
  local idx reason host sid hit
  if ! find_worktree_index "$1"; then
    STALE_NOTE="not a registered worktree: $1"
    return "$EX_ENV"
  fi
  idx="$WT_INDEX"
  reason="${WT_REASONS[idx]}"
  if ((WT_IS_LINKED[idx] == 0)) || [[ -z "$reason" ]]; then
    STALE_NOTE="not provable: ${WT_PATHS[idx]} is not a linked worktree with a lock reason"
    return "$EX_UNCLAIMED_REPORT"
  fi
  # Called for the BASH_REMATCH it sets, not its output, so no subshell runs.
  if ! worktree_reason_lane "$reason" >/dev/null; then
    STALE_NOTE="not provable: the lock reason names no session: $reason"
    return "$EX_UNCLAIMED_REPORT"
  fi
  host="${BASH_REMATCH[1]}"
  sid="${BASH_REMATCH[2]}"
  [[ -n "$THIS_HOST" ]] || THIS_HOST="$(worktree_host_name)"
  if [[ "$host" != "$THIS_HOST" ]]; then
    STALE_NOTE="not provable: the lock is from host $host, not this host"
    return "$EX_UNCLAIMED_REPORT"
  fi
  if ((batch)); then
    scan_transcripts '*.jsonl'
  else
    scan_transcripts "$sid.jsonl" -quit
  fi
  case "$TRANSCRIPT_SCAN" in
  unreadable)
    STALE_NOTE="not provable: transcript directory $TRANSCRIPT_DIR is unreadable"
    return "$EX_UNCLAIMED_REPORT"
    ;;
  failed)
    STALE_NOTE="not provable: scanning $TRANSCRIPT_DIR failed"
    return "$EX_UNCLAIMED_REPORT"
    ;;
  *) ;;
  esac
  if [[ "$TRANSCRIPTS" == *"/$sid.jsonl"$'\n'* ]]; then
    hit="${TRANSCRIPTS%%"/$sid.jsonl"$'\n'*}"
    STALE_NOTE="not provable: transcript ${hit##*$'\n'}/$sid.jsonl changed within $idle_minutes minutes"
    return "$EX_UNCLAIMED_REPORT"
  fi
  STALE_NOTE="stale: session $sid on $host has no transcript change in $idle_minutes minutes"
  return "$EX_OK"
}

do_stale() {
  local rc
  stale_verdict "$path"
  rc=$?
  if ((rc == EX_ENV)); then
    printf '%s: %s\n' "$PROG" "$STALE_NOTE" >&2
  else
    printf '%s\n' "$STALE_NOTE"
  fi
  return "$rc"
}

do_stale_batch() {
  local input canon rc i
  local -a inputs=()
  while IFS= read -r -d '' input || [[ -n "$input" ]]; do
    [[ -n "$input" ]] || continue
    if [[ "$input" == *$'\t'* || "$input" == *$'\n'* ]]; then
      printf '%s: stale --batch: a path holds a tab or newline: %q\n' "$PROG" "$input" >&2
      return "$EX_USAGE"
    fi
    inputs+=("$input")
  done
  [[ ${#inputs[@]} -gt 0 ]] || return "$EX_OK"
  for i in "${!inputs[@]}"; do
    canonicalize_path_to canon "${inputs[i]}"
    stale_verdict "$canon"
    rc=$?
    printf '%s\t%s\t%s\n' "$rc" "${inputs[i]}" "${STALE_NOTE//[$'\t\n']/ }"
  done
  return "$EX_OK"
}

case "$cmd" in
stale)
  if ((batch)); then
    do_stale_batch
    exit $?
  fi
  do_stale
  exit $?
  ;;
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
release)
  do_release
  exit $?
  ;;
# Unknown verbs already exited above, where the verb was validated.
*) ;;
esac
