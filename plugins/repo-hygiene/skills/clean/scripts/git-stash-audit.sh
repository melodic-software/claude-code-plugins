#!/usr/bin/env bash
# shellcheck disable=SC2154
# Stash audit facts for the clean git tier. No stash is ever dropped.
#
# Output contract (stable labels):
#   StashStore: <absolute git-common-dir | unknown>   (dedup key across worktrees)
#   per stash — Stash, Commit, Age days, Source branch, Diffstat, PR, Advisory
#   Stash count: <N>
#   Summary: stashes=<N> likely-superseded=<M> (never auto-dropped)
# `Stash` is the volatile `stash@{n}` selector (renumbers after every drop);
# `Commit` is the stash's stable object id — the safe handle when dropping more
# than one stash from a single audit.
# Exit: 0.
# Omit -e/-o pipefail: always exits 0; sub-commands are best-effort (gh may be absent).
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/clean-common.sh source=lib/cleanup-paths.sh
source "$SCRIPT_DIR/lib/clean-common.sh"

usage() {
  cat <<'EOF'
git-stash-audit.sh — emit stash audit facts for the clean git tier.

Usage:
  git-stash-audit.sh
  git-stash-audit.sh --help

Never drops a stash (read-only). Exit: 0.
EOF
}

case "${1:-}" in
-h | --help)
  usage
  exit 0
  ;;
*) ;;
esac

REPO_ROOT="$(clean_repo_root)"
if [[ -z "$REPO_ROOT" ]]; then
  echo "Error: not a git repository"
  exit 0
fi

# Linked worktrees share one stash ref (stored against the common git dir), so a
# fleet sweep visiting several worktrees of the same repo must dedup on this key
# rather than counting each worktree's identical stash list.
COMMON_DIR="$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | tr -d '\r')"
[[ -z "$COMMON_DIR" ]] && COMMON_DIR="$(git -C "$REPO_ROOT" rev-parse --git-common-dir 2>/dev/null | tr -d '\r')"
printf 'StashStore: %s\n' "${COMMON_DIR:-unknown}"

DEFAULT_BRANCH="$(git -C "$REPO_ROOT" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|^refs/remotes/origin/||' | tr -d '\r')"
if [[ -z "$DEFAULT_BRANCH" ]] && command -v gh >/dev/null 2>&1; then
  DEFAULT_BRANCH="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null | tr -d '\r')"
fi
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

# PR map (best-effort): source-branch → state, so a stash whose source branch was
# merged can be flagged likely-superseded. Same batched gh call as the branch audit.
declare -A PR_STATE=()
declare -A PR_NUM=()
if command -v gh >/dev/null 2>&1; then
  while IFS=$'\t' read -r head state num; do
    [[ -z "$head" ]] && continue
    PR_STATE["$head"]="$state"
    PR_NUM["$head"]="$num"
  done < <(gh pr list --state all --json headRefName,state,number --limit 200 2>/dev/null |
    jq -r '.[] | [.headRefName, .state, .number] | @tsv' 2>/dev/null | tr -d '\r')
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
