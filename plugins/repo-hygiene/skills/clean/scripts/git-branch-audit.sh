#!/usr/bin/env bash
# shellcheck disable=SC2154
# Branch audit facts for the clean git branch cleanup. No deletion.
#
# Output: PR-map status (PRCount, or PRDataUnavailable; PRDataTruncated when the
# lookup hit its cap); then per branch Branch, Tip, Tier, Age days, PR, Unpushed,
# Loss, Reason; then the LossBlock (LossBlock / LossBranch / LossCommit /
# LossBlockEnd); then TipCapture (or TipCaptureError); Summary line. A missing
# map is NOT the same as a repo with no PRs, and the two are distinguishable
# here on purpose: PR state is what detects a squash merge, so without it a
# landed branch reads as unmerged.
# Exit: 0 (2 on a usage error).
# Omit -e/-o pipefail: script always exits 0 on a successful run; sub-commands
# are best-effort (gh may be absent).
#
# LOSSY TIER. A branch is LOSSY when it is deletable and deleting it loses work:
# it would otherwise be REVIEW, origin/<default> is present so "landed" can be
# evaluated, and `git rev-list <branch> --not --remotes --tags` counts at least
# one commit reachable from no remote-tracking ref and no tag. Those commits
# exist only on this local branch. Other local branches deliberately do NOT
# count as "elsewhere": a sibling in the same deletion batch is not a place the
# work persists. A PR known to be MERGED (a squash changes the SHA, so the count
# would overstate the loss) or OPEN (an active claim on the branch) keeps the
# branch in REVIEW. Every missing or failed signal (no tip, no origin/<default>,
# a failed count) yields `Loss: undetermined` and REVIEW, never LOSSY and never
# SAFE. SAFE and LIKELY-SAFE are computed exactly as before; LOSSY is carved out
# of REVIEW only, so this tier can widen what an operator must confirm and can
# never narrow it.
#
# The LOSSY set is printed again as its own block after the per-branch records,
# one LossBranch line per branch with the commits that would be lost, so the
# operator confronts it as a separate decision before any deletion is
# confirmed: a prose flag beside a verdict column is the shape that once let
# five branches of unlanded work through a deletion pass.
#
# TIP CAPTURE. Every branch's tip commit is written, together with its verdict,
# upstream and ahead/behind counts, to a durable TSV under the repository's
# common git dir (`.git/repo-hygiene/branch-tips/<utc-stamp>-<pid>.tsv`), and
# the path is printed as `TipCapture: <path>`. That file is the precondition
# git-branch-delete.sh demands before it deletes anything: a deleted branch is
# restorable only from its tip, and the tip must be recorded BEFORE the delete,
# not remembered from a transcript. The capture is written to a `.part` file
# (created exclusively, so two runs can never share one) and renamed into place
# only when every row landed; any failure (no writable location, a short write)
# yields `TipCaptureError:` instead of a path, so a partial capture can never
# present itself as a complete one. Rows are recognised by shape (nine
# tab-separated columns, a commit id in the second), never by a leading `#`,
# which is a legal first character of a branch name.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/clean-common.sh source=lib/cleanup-paths.sh
source "$SCRIPT_DIR/lib/clean-common.sh"

usage() {
  cat <<'EOF'
git-branch-audit.sh - emit branch audit facts for the clean git tier.

Usage:
  git-branch-audit.sh [--capture-file PATH]
  git-branch-audit.sh --help

  --capture-file PATH  write the branch-tip capture to PATH instead of the
                       default <git-common-dir>/repo-hygiene/branch-tips/<utc-stamp>-<pid>.tsv

Per branch: Branch, Tip, Tier, Age days, PR, Unpushed, Loss, Reason.
Tiers: PROTECTED, WORKTREE, SAFE, LIKELY-SAFE, LOSSY, REVIEW. LOSSY is a branch
that is deletable but whose deletion loses commits present on no remote ref and
no tag; its `Loss:` line carries the count. A loss that cannot be determined is
`Loss: undetermined (<why>)` and the branch stays REVIEW.
Then the loss block, `LossBlock: <n> ...` to `LossBlockEnd: <n>`, listing every
LOSSY branch (LossBranch) and the commits it would lose (LossCommit, at most
CLEAN_LOSS_COMMITS_SHOWN per branch, default 10). Surface it as its own decision
before any deletion is confirmed; git-branch-delete.sh admits LOSSY only under
--accept-loss.
Then `TipCapture: <path>` (the durable tip record git-branch-delete.sh requires)
or `TipCaptureError: <why>` when it could not be written completely.
Restore a branch from a captured tip: git branch <branch> <tip>

Does NOT delete branches. Exit: 0 (2 on a usage error).
EOF
}

CAPTURE_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --capture-file)
    if [[ -z "${2:-}" ]]; then
      echo "git-branch-audit.sh: --capture-file requires a value" >&2
      exit 2
    fi
    CAPTURE_ARG="$2"
    shift 2
    ;;
  *)
    echo "git-branch-audit.sh: unknown arg '$1'" >&2
    usage >&2
    exit 2
    ;;
  esac
done

REPO_ROOT="$(clean_repo_root)"
if [[ -z "$REPO_ROOT" ]]; then
  echo "Error: not a git repository"
  exit 0
fi

DEFAULT_BRANCH="$(clean_default_branch "$REPO_ROOT")"

CURRENT_BRANCH="$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null | tr -d '\r')"

# Tip capture setup. The capture is opened before the first branch is classified
# and every row is appended as its branch is reported, so the file mirrors the
# output exactly. CAPTURE_ERROR, once set, is sticky: nothing after it can turn a
# failed capture back into a reported path.
CAPTURED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
COMMON_DIR="$(clean_git_common_dir "$REPO_ROOT")" || COMMON_DIR=""
CAPTURE_ERROR=""
CAPTURE_ROWS=0
if [[ -n "$CAPTURE_ARG" ]]; then
  CAPTURE_PATH="$CAPTURE_ARG"
elif [[ -n "$COMMON_DIR" ]]; then
  CAPTURE_PATH="$COMMON_DIR/repo-hygiene/branch-tips/$(date -u +%Y%m%dT%H%M%SZ)-$$.tsv"
else
  CAPTURE_PATH=""
  CAPTURE_ERROR="cannot resolve the git common dir for a default capture location; pass --capture-file PATH"
fi
CAPTURE_TMP="${CAPTURE_PATH}.part"
CAPTURE_TMP_OWNED=0
if [[ -z "$CAPTURE_ERROR" ]]; then
  # noclobber makes the create exclusive: a `.part` left by another run (a
  # <stamp>-<pid> collision across PID namespaces sharing the mount, or an
  # interrupted audit) is refused rather than appended to, so two runs can
  # never interleave rows into one file. The other run's file is left alone.
  if ! mkdir -p "$(dirname "$CAPTURE_PATH")" 2>/dev/null; then
    CAPTURE_ERROR="cannot create $(dirname "$CAPTURE_PATH")"
  elif ! (set -C && : >"$CAPTURE_TMP") 2>/dev/null; then
    if [[ -e "$CAPTURE_TMP" ]]; then
      CAPTURE_ERROR="refusing to reuse existing $CAPTURE_TMP (another audit is writing it, or one was interrupted); remove it or pass --capture-file PATH"
    else
      CAPTURE_ERROR="cannot write $CAPTURE_TMP"
    fi
  else
    CAPTURE_TMP_OWNED=1
  fi
fi

capture_line() {
  [[ -n "$CAPTURE_ERROR" ]] && return 0
  if ! printf '%s\n' "$1" >>"$CAPTURE_TMP" 2>/dev/null; then
    CAPTURE_ERROR="write failed: $CAPTURE_TMP"
  fi
}

capture_line "# repo-hygiene branch tip capture v1"
capture_line "# repo: $REPO_ROOT"
capture_line "# common_dir: ${COMMON_DIR:-unknown}"
capture_line "# default_branch: $DEFAULT_BRANCH"
capture_line "# captured_at: $CAPTURED_AT"
capture_line "# restore: git branch <branch> <tip>"
capture_line "$(printf '# columns: branch\ttip\ttier\tpr\tupstream\tahead\tbehind\tnot_on_default\tcaptured_at')"

# PR map: branch → state, the mitigation for squash merges that `git --merged`
# cannot see. clean_pr_map emits PRCount / PRDataTruncated / PRDataUnavailable
# onto this script's stdout, so a short or missing map is visible to the reader
# instead of silently degrading every SAFE/REVIEW verdict below.
declare -A PR_STATE=()
declare -A PR_NUM=()
declare -A PR_REFOID=()
PR_MAP_FILE="$(mktemp 2>/dev/null)" || PR_MAP_FILE="${TMPDIR:-/tmp}/clean-pr-map.$$"
trap 'rm -f "$PR_MAP_FILE"' EXIT
clean_pr_map "$PR_MAP_FILE" 'headRefName,state,number,headRefOid'
if [[ -f "$PR_MAP_FILE" ]]; then
  while IFS=$'\t' read -r head state num refoid; do
    [[ -z "$head" ]] && continue
    PR_STATE["$head"]="$state"
    PR_NUM["$head"]="$num"
    PR_REFOID["$head"]="$refoid"
  done <"$PR_MAP_FILE"
fi

WORKTREE_BRANCHES="$(git -C "$REPO_ROOT" worktree list --porcelain 2>/dev/null | grep '^branch' | sed 's|^branch refs/heads/||' | tr -d '\r')"
GONE_BRANCHES="$(git -C "$REPO_ROOT" branch -vv 2>/dev/null | grep ': gone]' | awk '{print $1}' | tr -d '\r')"
MERGED_BRANCHES="$(git -C "$REPO_ROOT" branch --merged "origin/${DEFAULT_BRANCH}" 2>/dev/null | sed 's/^[ *]*//' | grep -v "^${DEFAULT_BRANCH}$" | tr -d '\r' || true)"

prot=0 wt=0 safe=0 likely=0 lossy=0 review=0
NOW=$(date +%s)

# The LOSSY set, collected during classification and printed as its own block
# after the per-branch records. Parallel arrays indexed by position.
LOSSY_BRANCHES=()
LOSSY_COUNTS=()
LOSSY_REASONS=()
LOSSY_TIPS=()
LOSS_COMMITS_SHOWN="${CLEAN_LOSS_COMMITS_SHOWN:-10}"
[[ "$LOSS_COMMITS_SHOWN" =~ ^[0-9]+$ ]] || LOSS_COMMITS_SHOWN=10

# loss_count <branch> -> prints the number of commits on refs/heads/<branch>
# reachable from no remote-tracking ref and no tag; exit non-zero when git could
# not count. `--not --remotes --tags` is git's own idiom for "unpushed anywhere":
# it negates every ref under refs/remotes/ and refs/tags/, and nothing else, so
# another local branch, HEAD, and the refs/repo-hygiene/deleted/ pins are not
# places the work is considered to persist.
loss_count() {
  local n
  n="$(git -C "$REPO_ROOT" rev-list --count "refs/heads/$1" --not --remotes --tags 2>/dev/null)" || return 1
  n="${n%$'\r'}"
  [[ "$n" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$n"
}

classify_branch() {
  local branch="$1" age_days="$2" tier reason pr_line="none" local_tip
  local upstream no_upstream=0 ahead_default="" unpushed_line ahead_up behind_up=""
  local loss_line lost=""

  # The tip is the one fact that makes a deleted branch restorable, so it is
  # resolved first and reported for every branch regardless of verdict: a
  # verdict can be wrong in either direction, and the tip is what recovers from
  # that. An unresolvable tip is reported as such and gets no capture row, which
  # makes the branch undeletable through git-branch-delete.sh.
  local_tip="$(git -C "$REPO_ROOT" rev-parse --verify --quiet "refs/heads/$branch" 2>/dev/null | tr -d '\r')"

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
  elif [[ "${PR_STATE[$branch]:-}" == "MERGED" ]]; then
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
  elif [[ "${PR_STATE[$branch]:-}" == "CLOSED" ]]; then
    tier="REVIEW"
    reason="PR closed without merge"
    pr_line="#${PR_NUM[$branch]} CLOSED"
  elif grep -qxF "$branch" <<<"$GONE_BRANCHES"; then
    if [[ -z "$ahead_default" ]]; then
      # Upstream gone AND no origin/<default> to compare against (feature-only
      # clone, unfetched/missing remote HEAD): the script cannot prove the branch
      # is merged, so fail closed to REVIEW rather than offer it as a deletable
      # LIKELY-SAFE candidate that might carry local-only commits.
      tier="REVIEW"
      reason="upstream gone, cannot compare against origin/${DEFAULT_BRANCH}"
    elif [[ "$ahead_default" -gt 0 ]]; then
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

  # Loss assessment, and the REVIEW -> LOSSY refinement. Only a REVIEW verdict
  # is ever refined, and only upward into "deletable, loses work": every branch
  # the chain above already deemed safe keeps its verdict untouched, and every
  # signal that is missing or failed leaves the branch in REVIEW with the reason
  # spelled out. The boundary is therefore checkable: LOSSY iff REVIEW by the
  # chain, tip resolved, origin/<default> present, the count succeeded and is
  # positive, and the PR state is neither MERGED nor OPEN.
  case "$tier" in
  PROTECTED | WORKTREE | SAFE | LIKELY-SAFE)
    loss_line="not assessed ($tier)"
    ;;
  *)
    if [[ -z "$local_tip" ]]; then
      loss_line="undetermined (tip unresolved)"
    elif [[ -z "$ahead_default" ]]; then
      loss_line="undetermined (no origin/${DEFAULT_BRANCH} to compare against)"
    elif ! lost="$(loss_count "$branch")"; then
      lost=""
      loss_line="undetermined (could not count commits absent from every remote ref and tag)"
    elif [[ "$lost" -eq 0 ]]; then
      loss_line="none (every commit is on a remote ref or a tag)"
    else
      loss_line="${lost} commits only on this branch"
      case "${PR_STATE[$branch]:-}" in
      MERGED)
        # A squash merge lands the work under a new SHA, so the count above
        # overstates what a deletion loses; the tip drift already put the
        # branch in REVIEW and it stays there.
        loss_line+=" (PR merged; count unreliable after a squash, stays REVIEW)"
        ;;
      OPEN)
        loss_line+=" (PR open, stays REVIEW)"
        ;;
      *)
        tier="LOSSY"
        LOSSY_BRANCHES+=("$branch")
        LOSSY_COUNTS+=("$lost")
        LOSSY_REASONS+=("$reason")
        LOSSY_TIPS+=("$local_tip")
        ;;
      esac
    fi
    ;;
  esac

  case "$tier" in
  PROTECTED) prot=$((prot + 1)) ;;
  WORKTREE) wt=$((wt + 1)) ;;
  SAFE) safe=$((safe + 1)) ;;
  LIKELY-SAFE) likely=$((likely + 1)) ;;
  LOSSY) lossy=$((lossy + 1)) ;;
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
    behind_up="$(git -C "$REPO_ROOT" rev-list --count "refs/heads/${branch}..${branch}@{upstream}" 2>/dev/null | tr -d '\r')"
    unpushed_line="${ahead_up:-0} ahead of ${upstream}"
  fi

  printf 'Branch: %s\n' "$branch"
  printf 'Tip: %s\n' "${local_tip:-unresolved}"
  printf 'Tier: %s\n' "$tier"
  printf 'Age days: %s\n' "$age_days"
  printf 'PR: %s\n' "$pr_line"
  printf 'Unpushed: %s\n' "$unpushed_line"
  printf 'Loss: %s\n' "$loss_line"
  printf 'Reason: %s\n' "$reason"

  if [[ -n "$local_tip" ]]; then
    capture_line "$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
      "$branch" "$local_tip" "$tier" "$pr_line" "${upstream:-none}" \
      "${ahead_up:--}" "${behind_up:--}" "${ahead_default:--}" "$CAPTURED_AT")"
    CAPTURE_ROWS=$((CAPTURE_ROWS + 1))
  fi
}

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  branch="${line%% *}"
  ts="${line##* }"
  age_days=$(((NOW - ts) / 86400))
  classify_branch "$branch" "$age_days"
done < <(git -C "$REPO_ROOT" for-each-ref refs/heads/ --format='%(refname:short) %(committerdate:unix)' 2>/dev/null | tr -d '\r')

# The loss block: the LOSSY set again, as its own surface. It is printed even
# when empty so a reader can tell "no branch loses work" from "the block was
# never produced". Per branch: the count, the chain's reason, the tip, and the
# commits that would be lost (capped; the remainder is counted, not dropped
# silently).
if [[ ${#LOSSY_BRANCHES[@]} -eq 0 ]]; then
  printf 'LossBlock: 0 branches lose work if deleted\n'
else
  printf 'LossBlock: %s branches lose work if deleted; confirm them as their own decision, never with the SAFE/LIKELY-SAFE set\n' "${#LOSSY_BRANCHES[@]}"
  for i in "${!LOSSY_BRANCHES[@]}"; do
    b="${LOSSY_BRANCHES[$i]}"
    n="${LOSSY_COUNTS[$i]}"
    printf 'LossBranch: %s %s commits only on this branch (%s) tip %s\n' "$b" "$n" "${LOSSY_REASONS[$i]}" "${LOSSY_TIPS[$i]}"
    shown=0
    while IFS= read -r cl; do
      cl="${cl%$'\r'}"
      [[ -z "$cl" ]] && continue
      printf 'LossCommit: %s %s\n' "$b" "$cl"
      shown=$((shown + 1))
    done < <(git -C "$REPO_ROOT" log --format='%h %s' -n "$LOSS_COMMITS_SHOWN" "refs/heads/$b" --not --remotes --tags 2>/dev/null)
    if [[ "$n" -gt "$shown" ]]; then
      printf 'LossCommit: %s and %s more\n' "$b" "$((n - shown))"
    fi
  done
fi
printf 'LossBlockEnd: %s\n' "${#LOSSY_BRANCHES[@]}"

# Seal the capture: rename the .part into place only after a row count on the
# written file agrees with the rows this run produced. A short write (disk full,
# a vanished mount) therefore surfaces as TipCaptureError, never as a capture
# that silently lacks some of the branches the report above lists. A row is
# counted by shape: nine columns, a commit id in the second, this run's stamp in
# the last (a truncated row fails that test); a branch name beginning with `#`
# is a row like any other.
if [[ -z "$CAPTURE_ERROR" ]]; then
  written="$(awk -F'\t' -v at="$CAPTURED_AT" \
    'NF == 9 && $2 ~ /^[0-9a-f]+$/ && length($2) >= 40 && $9 == at { n++ } END { print n + 0 }' \
    "$CAPTURE_TMP" 2>/dev/null | tr -d '\r')"
  if [[ "${written:-x}" != "$CAPTURE_ROWS" ]]; then
    CAPTURE_ERROR="short write: expected $CAPTURE_ROWS rows, found ${written:-0} in $CAPTURE_TMP"
  elif ! mv -f "$CAPTURE_TMP" "$CAPTURE_PATH" 2>/dev/null; then
    CAPTURE_ERROR="cannot rename $CAPTURE_TMP into place"
  fi
fi
if [[ -n "$CAPTURE_ERROR" ]]; then
  [[ $CAPTURE_TMP_OWNED -eq 1 ]] && rm -f "$CAPTURE_TMP" 2>/dev/null
  printf 'TipCaptureError: %s\n' "$CAPTURE_ERROR"
else
  printf 'TipCapture: %s\n' "$CAPTURE_PATH"
fi

printf 'Summary: protected=%s worktree=%s safe=%s likely-safe=%s lossy=%s review=%s\n' "$prot" "$wt" "$safe" "$likely" "$lossy" "$review"
exit 0
