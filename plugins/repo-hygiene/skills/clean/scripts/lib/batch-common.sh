# shellcheck shell=bash
# Shared plumbing for the fleet (batch) clean orchestrator. Sourceable; not run
# directly. Reuses clean_path_key / clean_skip_matches from clean-common.sh —
# the separator-agnostic normalization + skip matching proven out by tree-batch.
#
# tree-batch (git-tree-reset-batch.sh) predates this module and still carries its
# own inline copies of read-lines / resolve-dedup / emit. This is the canonical
# home for that plumbing; migrating tree-batch onto it is a deferred follow-up,
# kept out of scope here so this change stays off tree-batch's large test suite.

# shellcheck source=clean-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/clean-common.sh"

# batch_normalize_input <path> — echo a git-friendly path: backslashes to forward
# slashes, strip a trailing CR, collapse trailing slashes. `ghq list -p` emits
# `D:\repos\...` — backslashes break `xargs` (escapes eaten) and bash `[[ -d ]]`;
# git and `git check-ignore` want the `D:/repos/...` drive-letter forward-slash
# form (git rev-parse --show-toplevel already emits it, so a normalized input
# compares equal to a resolved toplevel). Drive letter is preserved as-is.
batch_normalize_input() {
  local v="${1%$'\r'}"
  v="${v//\\//}"
  while [[ "$v" == */ && "$v" != "/" ]]; do v="${v%/}"; done
  printf '%s' "$v"
}

# batch_read_lines_into <array-name> <file|-> — append non-empty CR-stripped
# lines. Raw (unnormalized): repo paths are normalized at resolve time, skip
# entries are normalized by clean_skip_matches, so neither is pre-mangled here.
batch_read_lines_into() {
  local -n _dest="$1"
  local src="$2" line
  if [[ "$src" == "-" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%$'\r'}"
      [[ -n "$line" ]] && _dest+=("$line")
    done
  else
    [[ -f "$src" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%$'\r'}"
      [[ -n "$line" ]] && _dest+=("$line")
    done <"$src"
  fi
}

# Resolve-and-dedup accumulators, populated by batch_resolve_repos. Reset per call.
BATCH_TOPS=()
BATCH_KEYS=()
BATCH_INVALID=()
BATCH_INVALID_REASONS=()

# batch_resolve_repos <input>... — normalize each input, resolve to its canonical
# git toplevel, dedup by clean_path_key. A non-directory or non-git input is
# recorded in BATCH_INVALID / BATCH_INVALID_REASONS (surfaced as a blocked
# outcome by the caller) rather than silently dropped. Populates BATCH_TOPS /
# BATCH_KEYS with the surviving unique repos in first-seen order.
batch_resolve_repos() {
  BATCH_TOPS=()
  BATCH_KEYS=()
  BATCH_INVALID=()
  BATCH_INVALID_REASONS=()
  local input norm top key e seen
  for input in "$@"; do
    [[ -n "$input" ]] || continue
    norm="$(batch_normalize_input "$input")"
    [[ -n "$norm" ]] || continue
    if [[ ! -d "$norm" ]]; then
      BATCH_INVALID+=("$input")
      BATCH_INVALID_REASONS+=("not-a-directory")
      continue
    fi
    top="$(git -C "$norm" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
    if [[ -z "$top" ]]; then
      BATCH_INVALID+=("$input")
      BATCH_INVALID_REASONS+=("not-a-git-repo")
      continue
    fi
    key="$(clean_path_key "$top")"
    seen=0
    for e in "${BATCH_KEYS[@]}"; do
      [[ "$e" == "$key" ]] && {
        seen=1
        break
      }
    done
    ((seen)) && continue
    BATCH_TOPS+=("$top")
    BATCH_KEYS+=("$key")
  done
}

# Unique shared-object-store accumulators, populated by batch_add_gitdir.
BATCH_GITDIR_KEYS=()
BATCH_GITDIR_TOPS=()

# batch_reset_gitdirs — clear the git-common-dir dedup set (call once per run).
batch_reset_gitdirs() {
  BATCH_GITDIR_KEYS=()
  BATCH_GITDIR_TOPS=()
}

# batch_add_gitdir <repo_top> — resolve a repo's shared object store
# (`--git-common-dir`) and record it once. Linked worktrees share the main
# clone's objects, so git gc / prune must run once per unique common dir, not per
# worktree. The FIRST worktree top that maps to a common dir is kept as the
# representative to `cd` into (never the bare `.git` dir — prune/gc need a work
# tree cwd). Return: 0 newly added, 2 duplicate (already recorded), 1 unresolved.
batch_add_gitdir() {
  local top="$1" common key e
  common="$(git -C "$top" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | tr -d '\r')"
  if [[ -z "$common" ]]; then
    common="$(git -C "$top" rev-parse --git-common-dir 2>/dev/null | tr -d '\r')"
    [[ -n "$common" && "$common" != /* && "$common" != ?:/* ]] && common="$top/$common"
  fi
  [[ -n "$common" ]] || return 1
  key="$(clean_path_key "$common")"
  for e in "${BATCH_GITDIR_KEYS[@]}"; do
    [[ "$e" == "$key" ]] && return 2
  done
  BATCH_GITDIR_KEYS+=("$key")
  BATCH_GITDIR_TOPS+=("$top")
  return 0
}

# batch_emit <repo> <outcome> <reason> — one per-repo record block.
batch_emit() {
  printf 'Repo: %s\n' "$1"
  printf 'Outcome: %s\n' "$2"
  printf 'Reason: %s\n' "$3"
  printf '%s\n' '---'
}
