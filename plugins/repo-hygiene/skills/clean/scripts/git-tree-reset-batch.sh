#!/usr/bin/env bash
# Multi-repo working-tree realignment: run the single-repo git-tree-reset.sh
# `tree` tier across a set of repositories behind one confirmation gate, with a
# separator-agnostic skip list and a dirty-by-default guard.
#
# This is a thin orchestrator. It never runs a destructive git command itself:
# every reset/clean is delegated to the UNCHANGED git-tree-reset.sh, so every
# single-repo safety gate (upstream resolution, default-branch block, reset-
# success gate, reparse-point restore, unpushed-commit block) is reused verbatim.
# The batch layer adds only enumeration, skip-matching, the dirty guard, a per-
# repo outcome summary, and a single batch-wide dry-run -> confirm -> apply gate.
#
# Motivation: an ad-hoc `ghq list` reset loop reset --hard a repo it was meant to
# skip because the skip-match compared a Windows backslash path against a forward-
# slash path and silently failed, losing an uncommitted edit. Both defects are
# closed here: skip entries and enumerated repo paths are normalized to a
# canonical separator-agnostic key before comparison (clean_skip_matches), and
# dirty/unpushed repos are skipped unless --include-dirty is passed explicitly.
#
# Usage:
#   git-tree-reset-batch.sh [--dry-run|--apply]
#                           [--repo DIR]... [--repos-from FILE|-]...
#                           [--skip ENTRY]... [--skip-from FILE]...
#                           [--include-dirty]
#                           [--force-default-branch] [--include-deps]
#                           [--include-secrets] [--help]
# Default: --dry-run.
#
# Repo sources (a `ghq list`, a shell glob, or an explicit list all reduce to a
# path list): --repo (repeatable, and how a shell glob arrives after expansion),
# and --repos-from FILE (or - for stdin; how `ghq list -p` output is ingested).
#
# Skip list: --skip ENTRY (repeatable) / --skip-from FILE. An entry may be an
# absolute path or a trailing owner/repo or repo segment; matching is separator-
# agnostic. A skip entry that matches NO enumerated repo is reported as
# UnmatchedSkip so a typo can never silently fail to protect a repo again.
#
# Dirty guard: a repo with uncommitted or untracked changes OR unpushed commits
# is SKIPPED by default. --include-dirty opts in (and passes --allow-unpushed
# through so unpushed repos actually reset) -- this re-enables the exact data-loss
# vector, so the caller confirms it separately per the skill gate.
#
# Exit: 0 batch ran to completion (skips/blocks are normal, reported outcomes);
#       1 one or more repos failed mid-apply (child exit 5 -- partial reset);
#       2 usage/validation error (no repos, bad flag).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/clean-common.sh
source "$SCRIPT_DIR/lib/clean-common.sh"
TREE_RESET="$SCRIPT_DIR/git-tree-reset.sh"

usage() {
  cat <<'EOF'
git-tree-reset-batch.sh — run the tree reset across many repos behind one gate,
with a separator-agnostic skip list and a dirty-by-default guard.

Usage:
  git-tree-reset-batch.sh [--dry-run|--apply]
                          [--repo DIR]... [--repos-from FILE|-]...
                          [--skip ENTRY]... [--skip-from FILE]...
                          [--include-dirty]
                          [--force-default-branch] [--include-deps]
                          [--include-secrets] [--help]

Default: --dry-run (inventory only; no mutations).

Repo sources (combine freely; deduped by canonical toplevel):
  --repo DIR         a repository (repeatable; a shell glob expands to these).
  --repos-from FILE  newline-delimited repo paths (FILE, or - for stdin; the way
                     `ghq list -p` output is ingested). Repeatable.

Skip list (separator-agnostic; entry = absolute path or owner/repo or repo):
  --skip ENTRY       skip a repo (repeatable).
  --skip-from FILE   newline-delimited skip entries.

Dirty guard:
  --include-dirty    also reset repos with uncommitted/untracked changes or
                     unpushed commits (default: skip them). Passes --allow-unpushed
                     to the child. UNRECOVERABLE for uncommitted changes.

Passed through to git-tree-reset.sh per repo:
  --force-default-branch   allow repos checked out on their default branch
                           (a fresh-clone fleet is typically all on main).
  --include-deps           also remove node_modules/.venv/vendor.
  --include-secrets        also remove secrets / local config (UNRECOVERABLE).

Per-repo Outcome: would-reset | done | skipped | blocked. Reason names the cause.
Summary line: repos / reset / skipped / blocked / failed counts.

Exit: 0 ran to completion; 1 a repo failed mid-apply (child exit 5); 2 usage error.
EOF
}

DRY_RUN=1
INCLUDE_DIRTY=0
FORCE_DEFAULT=0
INCLUDE_DEPS=0
INCLUDE_SECRETS=0
REPO_INPUTS=()
SKIP_INPUTS=()

fail_usage() {
  echo "git-tree-reset-batch.sh: $1" >&2
  exit 2
}

read_lines_into() {
  # read_lines_into <array-name> <file|->  — append non-empty trimmed lines.
  local -n _dest="$1"
  local src="$2" line
  if [[ "$src" == "-" ]]; then
    while IFS= read -r line; do
      line="${line%$'\r'}"
      [[ -n "$line" ]] && _dest+=("$line")
    done
  else
    [[ -f "$src" ]] || fail_usage "file not found: $src"
    while IFS= read -r line; do
      line="${line%$'\r'}"
      [[ -n "$line" ]] && _dest+=("$line")
    done <"$src"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --dry-run) DRY_RUN=1 ;;
  --apply) DRY_RUN=0 ;;
  --include-dirty) INCLUDE_DIRTY=1 ;;
  --force-default-branch) FORCE_DEFAULT=1 ;;
  --include-deps) INCLUDE_DEPS=1 ;;
  --include-secrets) INCLUDE_SECRETS=1 ;;
  --repo)
    [[ $# -ge 2 ]] || fail_usage "--repo requires a directory"
    REPO_INPUTS+=("$2")
    shift
    ;;
  --repos-from)
    [[ $# -ge 2 ]] || fail_usage "--repos-from requires a file or -"
    read_lines_into REPO_INPUTS "$2"
    shift
    ;;
  --skip)
    [[ $# -ge 2 ]] || fail_usage "--skip requires an entry"
    SKIP_INPUTS+=("$2")
    shift
    ;;
  --skip-from)
    [[ $# -ge 2 ]] || fail_usage "--skip-from requires a file"
    read_lines_into SKIP_INPUTS "$2"
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) fail_usage "unknown arg '$1'" ;;
  esac
  shift
done

[[ ${#REPO_INPUTS[@]} -gt 0 ]] || fail_usage "no repos given (use --repo and/or --repos-from)"

# Resolve every input to its canonical toplevel and dedupe by comparison key.
# An input that is not a directory or not a git working tree is reported as a
# blocked outcome rather than silently dropped.
REPO_TOPS=()
REPO_KEYS=()
INVALID_INPUTS=()
INVALID_REASONS=()

key_seen() {
  local k="$1" e
  for e in "${REPO_KEYS[@]:-}"; do [[ "$e" == "$k" ]] && return 0; done
  return 1
}

for input in "${REPO_INPUTS[@]}"; do
  [[ -n "$input" ]] || continue
  if [[ ! -d "$input" ]]; then
    INVALID_INPUTS+=("$input")
    INVALID_REASONS+=("not-a-directory")
    continue
  fi
  top="$(git -C "$input" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  if [[ -z "$top" ]]; then
    INVALID_INPUTS+=("$input")
    INVALID_REASONS+=("not-a-git-repo")
    continue
  fi
  key="$(clean_path_key "$top")"
  key_seen "$key" && continue
  REPO_TOPS+=("$top")
  REPO_KEYS+=("$key")
done

# Per-skip match tracking so a skip that protects nothing is surfaced loudly.
SKIP_HITS=()
for ((s = 0; s < ${#SKIP_INPUTS[@]}; s++)); do SKIP_HITS+=(0); done

repo_dirty_reason() {
  # Echo a dirty reason (uncommitted/untracked or unpushed) or nothing if clean.
  local top="$1" porcelain ahead
  porcelain="$(git -C "$top" status --porcelain 2>/dev/null)"
  if [[ -n "$porcelain" ]]; then
    printf 'dirty (uncommitted or untracked changes)'
    return 0
  fi
  # Unpushed only counts when an upstream actually resolves; a repo with no
  # upstream is not "unpushed" (the child reports no-upstream when it runs).
  if git -C "$top" rev-parse --verify --quiet '@{u}' >/dev/null 2>&1; then
    ahead="$(git -C "$top" rev-list --count '@{u}..HEAD' 2>/dev/null | tr -d ' ' || echo 0)"
    if [[ "${ahead:-0}" -gt 0 ]]; then
      printf 'unpushed (%s commit(s) ahead of upstream)' "$ahead"
      return 0
    fi
  fi
  printf ''
}

# Flags passed through to the single-repo child for every repo that runs.
CHILD_PASS=()
[[ "$FORCE_DEFAULT" -eq 1 ]] && CHILD_PASS+=(--force-default-branch)
[[ "$INCLUDE_DEPS" -eq 1 ]] && CHILD_PASS+=(--include-deps)
[[ "$INCLUDE_SECRETS" -eq 1 ]] && CHILD_PASS+=(--include-secrets)
# --include-dirty accepts discarding unpushed commits too, so unblock the child's
# unpushed gate; a no-op when a repo is not ahead of its upstream.
[[ "$INCLUDE_DIRTY" -eq 1 ]] && CHILD_PASS+=(--allow-unpushed)

emit() {
  printf 'Repo: %s\n' "$1"
  printf 'Outcome: %s\n' "$2"
  printf 'Reason: %s\n' "$3"
  printf '%s\n' '---'
}

COUNT_RESET=0
COUNT_SKIPPED=0
COUNT_BLOCKED=0
COUNT_FAILED=0

printf 'Repo Fleet Tree Reset\n'
printf 'Mode: %s\n' "$([[ "$DRY_RUN" -eq 1 ]] && echo 'dry-run (no mutations)' || echo 'apply (destructive)')"
printf 'IncludeDirty: %s\n' "$([[ "$INCLUDE_DIRTY" -eq 1 ]] && echo yes || echo no)"
printf 'Repos: %s\n' "${#REPO_TOPS[@]}"
printf '%s\n' '---'

for ((i = 0; i < ${#REPO_TOPS[@]}; i++)); do
  top="${REPO_TOPS[$i]}"
  key="${REPO_KEYS[$i]}"

  # 1. Skip list (separator-agnostic).
  matched=""
  for ((s = 0; s < ${#SKIP_INPUTS[@]}; s++)); do
    if clean_skip_matches "$key" "${SKIP_INPUTS[$s]}"; then
      matched="${SKIP_INPUTS[$s]}"
      SKIP_HITS[s]=1
    fi
  done
  if [[ -n "$matched" ]]; then
    emit "$top" skipped "skip-list ($matched)"
    COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
    continue
  fi

  # 2. Dirty guard (skip unless --include-dirty).
  if [[ "$INCLUDE_DIRTY" -eq 0 ]]; then
    dirty="$(repo_dirty_reason "$top")"
    if [[ -n "$dirty" ]]; then
      emit "$top" skipped "$dirty (pass --include-dirty to reset anyway)"
      COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
      continue
    fi
  fi

  # 3. Delegate to the unchanged single-repo tree reset.
  rc=0
  out="$(cd "$top" && bash "$TREE_RESET" "$([[ "$DRY_RUN" -eq 1 ]] && echo --dry-run || echo --apply)" "${CHILD_PASS[@]}" 2>&1)" || rc=$?
  case "$rc" in
  0)
    if [[ "$DRY_RUN" -eq 1 ]]; then
      emit "$top" would-reset none
    else
      emit "$top" "done" none
    fi
    COUNT_RESET=$((COUNT_RESET + 1))
    ;;
  2)
    emit "$top" skipped "no upstream tracking branch"
    COUNT_SKIPPED=$((COUNT_SKIPPED + 1))
    ;;
  3)
    emit "$top" blocked "default-branch (pass --force-default-branch)"
    COUNT_BLOCKED=$((COUNT_BLOCKED + 1))
    ;;
  4)
    emit "$top" blocked "unpushed commits (pass --include-dirty)"
    COUNT_BLOCKED=$((COUNT_BLOCKED + 1))
    ;;
  5)
    emit "$top" failed "reset --hard failed mid-apply (child output below)"
    printf '%s\n' "$out" >&2
    COUNT_FAILED=$((COUNT_FAILED + 1))
    ;;
  6)
    emit "$top" blocked "upstream-unresolved"
    COUNT_BLOCKED=$((COUNT_BLOCKED + 1))
    ;;
  *)
    emit "$top" blocked "tree-reset error (child exit $rc)"
    COUNT_BLOCKED=$((COUNT_BLOCKED + 1))
    ;;
  esac
done

# Invalid inputs reported as blocked outcomes.
for ((i = 0; i < ${#INVALID_INPUTS[@]}; i++)); do
  emit "${INVALID_INPUTS[$i]}" blocked "${INVALID_REASONS[$i]}"
  COUNT_BLOCKED=$((COUNT_BLOCKED + 1))
done

# Surface skip entries that matched nothing — the silent-skip-failure that caused
# the original data loss now becomes a visible warning.
for ((s = 0; s < ${#SKIP_INPUTS[@]}; s++)); do
  if [[ "${SKIP_HITS[$s]}" -eq 0 ]]; then
    printf 'UnmatchedSkip: %s\n' "${SKIP_INPUTS[$s]}"
  fi
done

printf 'Summary: repos=%s reset=%s skipped=%s blocked=%s failed=%s\n' \
  "${#REPO_TOPS[@]}" "$COUNT_RESET" "$COUNT_SKIPPED" "$COUNT_BLOCKED" "$COUNT_FAILED"

[[ "$COUNT_FAILED" -eq 0 ]] || exit 1
exit 0
