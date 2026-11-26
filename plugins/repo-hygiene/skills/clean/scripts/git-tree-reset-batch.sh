#!/usr/bin/env bash
# Exit: 0 batch ran to completion (skips/blocks are normal, reported outcomes);
#       1 one or more repos failed mid-apply -- a partial destructive apply the
#         child reports non-zero: exit 5 (reset --hard failed) or exit 7 (reset
#         succeeded but git clean failed, so the tree is reset-but-not-cleaned);
#       2 usage/validation error (no repos, bad flag).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/batch-common.sh
source "$SCRIPT_DIR/lib/batch-common.sh"
TREE_RESET="$SCRIPT_DIR/git-tree-reset.sh"

usage() {
  cat <<'EOF'
git-tree-reset-batch.sh — run the tree reset across many repos behind one gate,
with a separator-agnostic skip list and a dirty-by-default guard.

Usage:
  git-tree-reset-batch.sh [--dry-run|--apply]
                          [--repo DIR...]... [--repos-from FILE|-]...
                          [--skip ENTRY]... [--skip-from FILE]...
                          [--include-dirty]
                          [--force-default-branch] [--include-deps]
                          [--include-secrets] [--help]

Default: --dry-run (inventory only; no mutations).

Repo sources (combine freely; deduped by canonical toplevel):
  --repo DIR...      one or more repositories (repeatable). Consumes every
                     consecutive non-flag path, so a shell glob (--repo
                     ~/repos/*) is ingested whole; consumption stops at the
                     next flag.
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

Per-repo Outcome: would-reset | done | skipped | blocked | failed. Reason names
the cause; a would-reset/done Reason also names discarded dirty edits (include-
dirty) and any files git clean could not remove (locked / in use).
Summary line: repos / reset / skipped / blocked / failed counts.

Exit: 0 ran to completion; 1 a repo failed mid-apply (child exit 5 or 7); 2 usage error.
EOF
}

DRY_RUN=1
INCLUDE_DIRTY=0
FORCE_DEFAULT=0
INCLUDE_DEPS=0
INCLUDE_SECRETS=0
REPO_INPUTS=()

fail_usage() {
  echo "git-tree-reset-batch.sh: $1" >&2
  exit 2
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
    [[ $# -ge 2 && "$2" != -* ]] || fail_usage "--repo requires a directory"
    shift
    while [[ $# -gt 0 && "$1" != -* ]]; do
      REPO_INPUTS+=("$1")
      shift
    done
    continue
    ;;
  --repos-from)
    [[ $# -ge 2 ]] || fail_usage "--repos-from requires a file or -"
    batch_read_lines_into REPO_INPUTS "$2" || fail_usage "file not found: $2"
    shift
    ;;
  --skip)
    [[ $# -ge 2 ]] || fail_usage "--skip requires an entry"
    BATCH_SKIP_INPUTS+=("$2")
    shift
    ;;
  --skip-from)
    [[ $# -ge 2 ]] || fail_usage "--skip-from requires a file"
    batch_read_lines_into BATCH_SKIP_INPUTS "$2" || fail_usage "file not found: $2"
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

REPO_TOPS=()
REPO_KEYS=()
INVALID_INPUTS=()
INVALID_REASONS=()

key_seen() {
  local k="$1" e
  for e in ${REPO_KEYS[@]+"${REPO_KEYS[@]}"}; do [[ "$e" == "$k" ]] && return 0; done
  return 1
}

for input in ${REPO_INPUTS[@]+"${REPO_INPUTS[@]}"}; do
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

batch_reset_skip_hits

repo_dirty_reason() {
  local top="$1" porcelain ahead
  porcelain="$(git -C "$top" status --porcelain 2>/dev/null)"
  if [[ -n "$porcelain" ]]; then
    printf 'dirty (uncommitted or untracked changes)'
    return 0
  fi
  if git -C "$top" rev-parse --verify --quiet '@{u}' >/dev/null 2>&1; then
    ahead="$(git -C "$top" rev-list --count '@{u}..HEAD' 2>/dev/null | tr -d ' ' || echo 0)"
    if [[ "${ahead:-0}" -gt 0 ]]; then
      printf 'unpushed (%s commit(s) ahead of upstream)' "$ahead"
    fi
  fi
}

child_label() { sed -n "s/^$2: //p" <<<"$1" | head -1; }

CHILD_MODE=--dry-run
[[ "$DRY_RUN" -eq 1 ]] || CHILD_MODE=--apply

CHILD_PASS=()
[[ "$FORCE_DEFAULT" -eq 1 ]] && CHILD_PASS+=(--force-default-branch)
[[ "$INCLUDE_DEPS" -eq 1 ]] && CHILD_PASS+=(--include-deps)
[[ "$INCLUDE_SECRETS" -eq 1 ]] && CHILD_PASS+=(--include-secrets)
[[ "$INCLUDE_DIRTY" -eq 1 ]] && CHILD_PASS+=(--allow-unpushed)

COUNT_RESET=0
COUNT_SKIPPED=0
COUNT_BLOCKED=0
COUNT_FAILED=0

record() {
  batch_emit "$1" "$2" "$3"
  case "$2" in
  skipped) COUNT_SKIPPED=$((COUNT_SKIPPED + 1)) ;;
  blocked) COUNT_BLOCKED=$((COUNT_BLOCKED + 1)) ;;
  failed) COUNT_FAILED=$((COUNT_FAILED + 1)) ;;
  *) COUNT_RESET=$((COUNT_RESET + 1)) ;;
  esac
}

add_reason() {
  if [[ "$reason" == none ]]; then reason="$1"; else reason="$reason; $1"; fi
}

printf 'Repo Fleet Tree Reset\n'
printf 'Mode: %s\n' "$([[ "$DRY_RUN" -eq 1 ]] && echo 'dry-run (no mutations)' || echo 'apply (destructive)')"
printf 'IncludeDirty: %s\n' "$([[ "$INCLUDE_DIRTY" -eq 1 ]] && echo yes || echo no)"
printf 'Repos: %s\n' "${#REPO_TOPS[@]}"
printf '%s\n' '---'

for ((i = 0; i < ${#REPO_TOPS[@]}; i++)); do
  top="${REPO_TOPS[$i]}"
  key="${REPO_KEYS[$i]}"

  if batch_skip_match "$key"; then
    record "$top" skipped "skip-list ($BATCH_SKIP_MATCHED)"
    continue
  fi

  if [[ "$INCLUDE_DIRTY" -eq 0 ]]; then
    dirty="$(repo_dirty_reason "$top")"
    if [[ -n "$dirty" ]]; then
      record "$top" skipped "$dirty (pass --include-dirty to reset anyway)"
      continue
    fi
  fi

  rc=0
  out="$(cd "$top" && bash "$TREE_RESET" "$CHILD_MODE" ${CHILD_PASS[@]+"${CHILD_PASS[@]}"} 2>&1)" || rc=$?
  case "$rc" in
  0)
    tracked_dirty="$(child_label "$out" TrackedDirty)"
    ahead="$(child_label "$out" AheadCount)"
    reason=none
    if [[ "$INCLUDE_DIRTY" -eq 1 ]]; then
      verb="$([[ "$DRY_RUN" -eq 1 ]] && echo 'would be discarded' || echo 'discarded')"
      [[ "${tracked_dirty:-0}" -gt 0 ]] && add_reason "$tracked_dirty uncommitted/untracked change(s) $verb"
      [[ "${ahead:-0}" -gt 0 ]] && add_reason "$ahead unpushed commit(s) $verb"
    fi
    if [[ "$DRY_RUN" -eq 1 ]]; then
      record "$top" would-reset "$reason"
    else
      unremovable="$(child_label "$out" Unremovable)"
      if [[ "${unremovable:-0}" -gt 0 ]]; then
        add_reason "incomplete clean: $unremovable path(s) unremovable (locked / in use)"
        printf '%s\n' "$out" | grep -E 'could not be removed|failed to remove' >&2 || true
      fi
      record "$top" "done" "$reason"
    fi
    ;;
  2) record "$top" skipped "no upstream tracking branch" ;;
  3) record "$top" blocked "default-branch (pass --force-default-branch)" ;;
  4)
    record "$top" blocked "unpushed commits after fetch (pass --include-dirty)"
    ;;
  5)
    record "$top" failed "reset --hard failed mid-apply (child output below)"
    printf '%s\n' "$out" >&2
    ;;
  7)
    record "$top" failed "clean failed after a successful reset -- partial apply, tree not fully cleaned (child output below)"
    printf '%s\n' "$out" >&2
    ;;
  6) record "$top" blocked "upstream-unresolved" ;;
  *) record "$top" blocked "tree-reset error (child exit $rc)" ;;
  esac
done

for ((i = 0; i < ${#INVALID_INPUTS[@]}; i++)); do
  record "${INVALID_INPUTS[$i]}" blocked "${INVALID_REASONS[$i]}"
done

batch_report_unmatched_skips

printf 'Summary: repos=%s reset=%s skipped=%s blocked=%s failed=%s\n' \
  "${#REPO_TOPS[@]}" "$COUNT_RESET" "$COUNT_SKIPPED" "$COUNT_BLOCKED" "$COUNT_FAILED"

[[ "$COUNT_FAILED" -eq 0 ]] || exit 1
exit 0
