#!/usr/bin/env bash
# shellcheck disable=SC2154
# Branch audit facts for the clean git branch cleanup. No deletion.
#
# Output: Branch, Tier, Age days, PR, Unpushed, Reason; Summary line.
# Exit: 0.
# Omit -e/-o pipefail: script always exits 0; sub-commands are best-effort (gh may be absent).
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/clean-common.sh source=lib/cleanup-paths.sh
source "$SCRIPT_DIR/lib/clean-common.sh"

usage() {
  cat <<'EOF'
git-branch-audit.sh — emit branch audit facts for the clean git tier.

Usage:
  git-branch-audit.sh
  git-branch-audit.sh --help

Does NOT delete branches. Exit: 0.
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

DEFAULT_BRANCH="$(git -C "$REPO_ROOT" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|^refs/remotes/origin/||' | tr -d '\r')"
if [[ -z "$DEFAULT_BRANCH" ]] && command -v gh >/dev/null 2>&1; then
  DEFAULT_BRANCH="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null | tr -d '\r')"
fi
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

CURRENT_BRANCH="$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null | tr -d '\r')"

declare -A PR_STATE=()
declare -A PR_NUM=()
declare -A PR_REFOID=()
if command -v gh >/dev/null 2>&1; then
  while IFS=$'\t' read -r head state num refoid; do
    [[ -z "$head" ]] && continue
    PR_STATE["$head"]="$state"
    PR_NUM["$head"]="$num"
    PR_REFOID["$head"]="$refoid"
  done < <(gh pr list --state all --json headRefName,state,number,headRefOid --limit 200 2>/dev/null |
    jq -r '.[] | [.headRefName, .state, .number, .headRefOid] | @tsv' 2>/dev/null | tr -d '\r')
fi

WORKTREE_BRANCHES="$(git -C "$REPO_ROOT" worktree list --porcelain 2>/dev/null | grep '^branch' | sed 's|^branch refs/heads/||' | tr -d '\r')"
GONE_BRANCHES="$(git -C "$REPO_ROOT" branch -vv 2>/dev/null | grep ': gone]' | awk '{print $1}' | tr -d '\r')"
MERGED_BRANCHES="$(git -C "$REPO_ROOT" branch --merged "origin/${DEFAULT_BRANCH}" 2>/dev/null | sed 's/^[ *]*//' | grep -v "^${DEFAULT_BRANCH}$" | tr -d '\r' || true)"

prot=0 wt=0 safe=0 likely=0 review=0
NOW=$(date +%s)

classify_branch() {
  local branch="$1" age_days="$2" tier reason pr_line="none" local_tip
  local upstream no_upstream=0 ahead_default="" unpushed_line ahead_up

  # No-upstream branches are invisible to `@{upstream}`-based ahead/behind
  # reporting (it yields nothing), so never-pushed local work goes unseen. Detect
  # the missing upstream and, when origin/<default> exists, count the branch's
  # commits absent from it — surfaced below as its own class and Unpushed line.
  # `rev-parse --abbrev-ref` echoes its input to stdout on failure (no upstream
  # configured, or a configured upstream whose tracking ref is unfetched), so gate
  # on its exit status rather than on empty output — otherwise that echo reads as a
  # real upstream.
  if upstream="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref "${branch}@{upstream}" 2>/dev/null)"; then
    upstream="${upstream%$'\r'}"
  else
    upstream=""
  fi
  [[ -z "$upstream" ]] && no_upstream=1
  # Commits on this branch absent from origin/<default> — the work lost if the
  # branch were deleted. Computed for every branch (when origin/<default> exists)
  # so both the upstream-gone and no-upstream classes can guard deletion on it: a
  # `gone` upstream normally means merged-and-deleted, but a gone branch still
  # carrying such commits is unmerged local work, not a safe-delete candidate.
  if git -C "$REPO_ROOT" rev-parse --verify --quiet "refs/remotes/origin/${DEFAULT_BRANCH}" >/dev/null 2>&1; then
    ahead_default="$(git -C "$REPO_ROOT" rev-list --count "origin/${DEFAULT_BRANCH}..refs/heads/${branch}" 2>/dev/null | tr -d '\r')"
  fi

  if [[ "$branch" == "$CURRENT_BRANCH" ]]; then
    tier="PROTECTED"
    reason="current branch"
  elif [[ "$branch" == "$DEFAULT_BRANCH" ]]; then
    tier="PROTECTED"
    reason="default branch"
  elif clean_branch_matches_protected_pattern "$branch"; then
    tier="PROTECTED"
    reason="protected pattern"
  elif grep -qxF "$branch" <<<"$WORKTREE_BRANCHES"; then
    tier="WORKTREE"
    reason="checked out in worktree — clean up the worktree first"
  elif [[ -n "${PR_STATE[$branch]:-}" && "${PR_STATE[$branch]}" == "MERGED" ]]; then
    local_tip="$(git -C "$REPO_ROOT" rev-parse "refs/heads/$branch" 2>/dev/null | tr -d '\r')"
    if [[ -n "${PR_REFOID[$branch]:-}" && -n "$local_tip" && "$local_tip" != "${PR_REFOID[$branch]}" ]]; then
      tier="REVIEW"
      reason="PR merged but branch has commits since merge"
      pr_line="#${PR_NUM[$branch]} MERGED (tip drift)"
    else
      tier="SAFE"
      reason="PR merged"
      pr_line="#${PR_NUM[$branch]} MERGED"
    fi
  elif grep -qxF "$branch" <<<"$MERGED_BRANCHES"; then
    tier="SAFE"
    reason="merged (git ancestry)"
  elif [[ -n "${PR_STATE[$branch]:-}" && "${PR_STATE[$branch]}" == "CLOSED" ]]; then
    tier="REVIEW"
    reason="PR closed without merge"
    pr_line="#${PR_NUM[$branch]} CLOSED"
  elif grep -qxF "$branch" <<<"$GONE_BRANCHES"; then
    if [[ -n "$ahead_default" && "$ahead_default" -gt 0 ]]; then
      tier="REVIEW"
      reason="upstream gone, ${ahead_default} commits not on origin/${DEFAULT_BRANCH}"
    else
      tier="LIKELY-SAFE"
      reason="upstream gone"
    fi
  elif [[ "$no_upstream" == 1 && -n "$ahead_default" && "$ahead_default" -gt 0 ]]; then
    tier="REVIEW"
    reason="no upstream, ${ahead_default} commits not on origin/${DEFAULT_BRANCH}"
  elif [[ "$age_days" -gt "$CLEAN_STALE_BRANCH_DAYS" ]]; then
    tier="REVIEW"
    reason="stale (${age_days}d)"
  else
    tier="REVIEW"
    reason="orphaned or needs review"
  fi

  case "$tier" in
  PROTECTED) prot=$((prot + 1)) ;;
  WORKTREE) wt=$((wt + 1)) ;;
  SAFE) safe=$((safe + 1)) ;;
  LIKELY-SAFE) likely=$((likely + 1)) ;;
  *) review=$((review + 1)) ;;
  esac

  if [[ -n "${PR_STATE[$branch]:-}" && "$pr_line" == "none" ]]; then
    pr_line="#${PR_NUM[$branch]} ${PR_STATE[$branch]}"
  fi

  if [[ "$no_upstream" == 1 ]]; then
    if [[ -n "$ahead_default" ]]; then
      unpushed_line="no upstream, ${ahead_default} commits not on origin/${DEFAULT_BRANCH}"
    else
      unpushed_line="no upstream (no origin/${DEFAULT_BRANCH} to compare)"
    fi
  else
    ahead_up="$(git -C "$REPO_ROOT" rev-list --count "${branch}@{upstream}..refs/heads/${branch}" 2>/dev/null | tr -d '\r')"
    unpushed_line="${ahead_up:-0} ahead of ${upstream}"
  fi

  printf 'Branch: %s\n' "$branch"
  printf 'Tier: %s\n' "$tier"
  printf 'Age days: %s\n' "$age_days"
  printf 'PR: %s\n' "$pr_line"
  printf 'Unpushed: %s\n' "$unpushed_line"
  printf 'Reason: %s\n' "$reason"
}

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  branch="${line%% *}"
  ts="${line##* }"
  age_days=$(((NOW - ts) / 86400))
  classify_branch "$branch" "$age_days"
done < <(git -C "$REPO_ROOT" for-each-ref refs/heads/ --format='%(refname:short) %(committerdate:unix)' 2>/dev/null | tr -d '\r')

printf 'Summary: protected=%s worktree=%s safe=%s likely-safe=%s review=%s\n' "$prot" "$wt" "$safe" "$likely" "$review"
exit 0
