#!/usr/bin/env bash
# shellcheck disable=SC2154
# Stash audit facts for the clean git tier. No stash is ever dropped.
#
# Output contract (stable labels):
#   StashStore: <absolute git-common-dir | unknown>   (dedup key across worktrees)
#   PRCount: <n>  OR  PRDataUnavailable: <why>        (PR map status; exactly one)
#   PRDataTruncated: <why>                            (only when the cap was hit)
#   per stash — Stash, Commit, Age days, Source branch, Diffstat, PR, Advisory
#   Stash count: <N>
#   Summary: stashes=<N> likely-superseded=<M> (never auto-dropped)
# `Stash` is the volatile `stash@{n}` selector (renumbers after every drop);
# `Commit` is the stash's stable object id — the safe handle when dropping more
# than one stash from a single audit.
# Exit: 0 (2 on a usage error).
# Omit -e/-o pipefail: always exits 0; sub-commands are best-effort (gh may be absent).
#
# FLEET FORM. --repo / --repos-from select repositories and --skip / --skip-from
# exclude some (the surface clean-batch.sh has, resolved by lib/batch-common.sh).
# Each audited repo is this same script run from inside it, one after another,
# printed as `Repo: <path>` then its unchanged output. A repo whose git common
# dir (the StashStore key) was already audited is reported skipped, and a repo
# that fails is reported without stopping the rest.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/clean-common.sh source=lib/cleanup-paths.sh
source "$SCRIPT_DIR/lib/clean-common.sh"
# shellcheck source=lib/batch-common.sh
source "$SCRIPT_DIR/lib/batch-common.sh"

usage() {
  cat <<'EOF'
git-stash-audit.sh — emit stash audit facts for the clean git tier.

Usage:
  git-stash-audit.sh
  git-stash-audit.sh [--repo DIR...]... [--repos-from FILE|-]...
                     [--skip ENTRY]... [--skip-from FILE]...
  git-stash-audit.sh --help

  --repo DIR...      audit these repositories instead of the current one
                     (repeatable; takes every consecutive non-flag path, so a
                     shell glob works)
  --repos-from FILE  newline-delimited repo paths (FILE, or - for stdin)
  --skip ENTRY       skip a repo: absolute path, owner/repo, or repo (repeatable)
  --skip-from FILE   newline-delimited skip entries

With --repo / --repos-from the repositories are audited one after another. Each
block is `Repo: <path>`, the output of a single-repo run, then `---`. A repo
sharing a git common dir (the `StashStore:` key) with an audited one, such as a
linked worktree, is reported `Outcome: skipped` so its stashes are listed once; a
skip-listed, unresolvable, or failing repo is reported without stopping the rest;
`FleetSummary: repos=N audited=A skipped=S duplicate=D blocked=B failed=F` closes
the run (exit 0).

Never drops a stash (read-only). Exit: 0 (2 on a usage error).
EOF
}

FLEET=0
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --repo | --repos-from | --skip | --skip-from)
    if ! batch_take_selection_arg "$@"; then
      echo "git-stash-audit.sh: $BATCH_ARG_ERROR" >&2
      exit 2
    fi
    [[ "$1" == --skip* ]] || FLEET=1
    shift "$BATCH_ARG_SHIFT"
    ;;
  *)
    echo "git-stash-audit.sh: unknown arg '$1'" >&2
    usage >&2
    exit 2
    ;;
  esac
done

if [[ $FLEET -eq 0 && ${#BATCH_SKIP_INPUTS[@]} -gt 0 ]]; then
  echo "git-stash-audit.sh: --skip / --skip-from need --repo or --repos-from" >&2
  exit 2
fi
if [[ $FLEET -eq 1 ]]; then
  if [[ ${#BATCH_REPO_INPUTS[@]} -eq 0 ]]; then
    echo "git-stash-audit.sh: no repos given (use --repo and/or --repos-from)" >&2
    exit 2
  fi
  batch_resolve_repos "${BATCH_REPO_INPUTS[@]}"
  batch_run_fleet "$SCRIPT_DIR/git-stash-audit.sh"
  exit 0
fi

REPO_ROOT="$(clean_repo_root)"
if [[ -z "$REPO_ROOT" ]]; then
  echo "Error: not a git repository"
  exit 0
fi

# Linked worktrees share one stash ref (stored against the common git dir), so a
# sweep visiting several worktrees of the same repo dedups on this key (the fleet
# form does it itself) rather than counting each worktree's identical stash list.
COMMON_DIR="$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | tr -d '\r')"
[[ -z "$COMMON_DIR" ]] && COMMON_DIR="$(git -C "$REPO_ROOT" rev-parse --git-common-dir 2>/dev/null | tr -d '\r')"
printf 'StashStore: %s\n' "${COMMON_DIR:-unknown}"

DEFAULT_BRANCH="$(clean_default_branch "$REPO_ROOT")"

# PR map (best-effort): source-branch → state, so a stash whose source branch was
# merged can be flagged likely-superseded. Same shared lookup as the branch audit,
# including its PRCount / PRDataTruncated / PRDataUnavailable status lines: a
# short or missing map silently withholds the superseded advisory, so it is
# reported rather than swallowed.
declare -A PR_STATE=()
declare -A PR_NUM=()
PR_MAP_FILE="$(mktemp 2>/dev/null)" || PR_MAP_FILE="${TMPDIR:-/tmp}/clean-pr-map.$$"
trap 'rm -f "$PR_MAP_FILE"' EXIT
clean_pr_map "$PR_MAP_FILE" 'headRefName,state,number'
if [[ -f "$PR_MAP_FILE" ]]; then
  while IFS=$'\t' read -r head state num; do
    [[ -z "$head" ]] && continue
    PR_STATE["$head"]="$state"
    PR_NUM["$head"]="$num"
  done <"$PR_MAP_FILE"
fi

NOW=$(date +%s)
count=0 superseded=0

while IFS=$'\t' read -r sel sha ts subject; do
  [[ -z "$sel" ]] && continue
  count=$((count + 1))
  age_days=$(((NOW - ts) / 86400))
  # Source branch from the stash subject ("WIP on X: …" / "On X: …").
  src="$(printf '%s' "$subject" | sed -n 's/^\(WIP on\|On\) \([^:]*\):.*/\2/p')"
  src="${src:-unknown}"
  # Prefer the untracked-inclusive stat (a `stash -u` pre-rebase backup is often
  # all untracked, invisible to the default stat); fall back to the tracked-only
  # stat on git too old for --include-untracked, then to a plain marker.
  diffstat="$(git -C "$REPO_ROOT" stash show --include-untracked --stat "$sel" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//')"
  [[ -z "$diffstat" ]] && diffstat="$(git -C "$REPO_ROOT" stash show --stat "$sel" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//')"
  [[ -z "$diffstat" ]] && diffstat="(no tracked changes)"

  pr_line="none"
  advisory="review — confirm with the user before dropping (never auto-dropped)"
  if [[ "$src" != "unknown" && -n "${PR_STATE[$src]:-}" ]]; then
    pr_line="#${PR_NUM[$src]} ${PR_STATE[$src]}"
    if [[ "${PR_STATE[$src]}" == "MERGED" ]]; then
      advisory="likely superseded — source branch PR merged; still confirm before dropping"
      superseded=$((superseded + 1))
    fi
  elif [[ "$src" != "unknown" && "$src" != "$DEFAULT_BRANCH" ]] &&
    git -C "$REPO_ROOT" rev-parse --verify --quiet "refs/remotes/origin/${DEFAULT_BRANCH}" >/dev/null 2>&1 &&
    git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/${src}" &&
    [[ -z "$(git -C "$REPO_ROOT" rev-list "origin/${DEFAULT_BRANCH}..refs/heads/${src}" 2>/dev/null | head -1)" ]]; then
    # No PR record but the source branch is fully merged into origin/<default>:
    # its committed work is on the default branch, so the stash is more likely a
    # superseded pre-merge backup. The stash's own diff may still be unique — hence
    # advisory only, never auto-drop.
    advisory="possibly superseded — source branch merged into origin/${DEFAULT_BRANCH}; confirm before dropping"
    superseded=$((superseded + 1))
  fi

  printf 'Stash: %s\n' "$sel"
  printf 'Commit: %s\n' "$sha"
  printf 'Age days: %s\n' "$age_days"
  printf 'Source branch: %s\n' "$src"
  printf 'Diffstat: %s\n' "$diffstat"
  printf 'PR: %s\n' "$pr_line"
  printf 'Advisory: %s\n' "$advisory"
done < <(git -C "$REPO_ROOT" stash list --format='%gd%x09%H%x09%ct%x09%gs' 2>/dev/null | tr -d '\r')

printf 'Stash count: %s\n' "$count"
printf 'Summary: stashes=%s likely-superseded=%s (never auto-dropped)\n' "$count" "$superseded"
exit 0
