#!/usr/bin/env bash
# The clean git tier's ONLY sanctioned local-branch deletion path (§4.7).
#
# Deletion here is gated on a branch-tip capture produced by git-branch-audit.sh
# (its `TipCapture: <path>` line). The script refuses to delete anything unless
# every branch in the batch has a captured tip AND that tip still matches the
# branch's current tip. It is a refusal, not a warning: an operator working
# through eighty branches skims warnings, and a branch deleted without a
# recorded tip has no reflog to come back from.
#
# Per branch, in this order, and only in --apply mode:
#   1. re-verify the live tip against the captured tip (stale plan guard),
#   2. pin the tip under refs/repo-hygiene/deleted/<branch> so gc cannot prune
#      the commits out from under the recorded identifier,
#   3. append the deletion to the capture's ledger (<capture>.deleted.tsv),
#   4. only then `git branch -d|-D <branch>`.
# Any failure in 1 to 3 aborts the batch BEFORE that branch is touched; branches
# already deleted keep their backup ref and ledger row. The batch-wide
# precondition check (capture present, every branch captured, every tip
# unmoved, no protected/worktree/unforced-REVIEW branch) runs before the first
# deletion, so a refused batch deletes nothing at all.
#
# Usage:
#   git-branch-delete.sh --capture PATH [--dry-run] [--force-review] BRANCH...
#   git-branch-delete.sh --capture PATH --apply   [--force-review] BRANCH...
#
# Restore a deleted branch:  git branch <branch> <tip>
#   (<tip> is in the capture, in the ledger, and under refs/repo-hygiene/deleted/<branch>)
#
# Exit: 0 planned (dry-run) or every branch deleted; 1 a deletion failed or the
# batch aborted mid-way; 2 usage error; 3 refused (precondition unmet, nothing
# deleted).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/clean-common.sh source=lib/cleanup-paths.sh
source "$SCRIPT_DIR/lib/clean-common.sh"

usage() {
  cat <<'EOF'
git-branch-delete.sh - delete local branches, gated on a captured tip per branch.

Usage:
  git-branch-delete.sh --capture PATH [--dry-run] [--force-review] BRANCH...
  git-branch-delete.sh --capture PATH --apply   [--force-review] BRANCH...
  git-branch-delete.sh --help

  --capture PATH   the TipCapture: file written by git-branch-audit.sh (required)
  --dry-run        default; check every precondition and print the plan
  --apply          delete, after pinning each tip under refs/repo-hygiene/deleted/
  --force-review   allow REVIEW-tier branches (SAFE and LIKELY-SAFE need no flag;
                   PROTECTED and WORKTREE are never deletable here)

Refuses the whole batch (exit 3, nothing deleted) when the capture is missing,
a branch has no captured tip, or a captured tip no longer matches the branch.
Re-run git-branch-audit.sh to produce a fresh capture.

Restore a deleted branch:  git branch <branch> <tip>

Exit: 0 ok; 1 a deletion failed or the batch aborted; 2 usage; 3 refused.
EOF
}

MODE="dry-run"
CAPTURE=""
FORCE_REVIEW=0
BRANCHES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --dry-run)
    MODE="dry-run"
    shift
    ;;
  --apply)
    MODE="apply"
    shift
    ;;
  --force-review)
    FORCE_REVIEW=1
    shift
    ;;
  --capture)
    if [[ -z "${2:-}" ]]; then
      echo "git-branch-delete.sh: --capture requires a value" >&2
      exit 2
    fi
    CAPTURE="$2"
    shift 2
    ;;
  --)
    shift
    while [[ $# -gt 0 ]]; do
      BRANCHES+=("$1")
      shift
    done
    ;;
  -*)
    echo "git-branch-delete.sh: unknown arg '$1'" >&2
    usage >&2
    exit 2
    ;;
  *)
    BRANCHES+=("$1")
    shift
    ;;
  esac
done

if [[ ${#BRANCHES[@]} -eq 0 ]]; then
  echo "git-branch-delete.sh: no branches given" >&2
  usage >&2
  exit 2
fi

REPO_ROOT="$(clean_repo_root)"
if [[ -z "$REPO_ROOT" ]]; then
  echo "git-branch-delete.sh: not a git repository" >&2
  exit 2
fi

# ---- Batch-wide precondition: the capture itself -----------------------------
# Every refusal is printed as its own `Refused:` line and the batch stops with
# nothing deleted. The message names what is missing and how to produce it.

REFUSED=0
refuse() {
  printf 'Refused: %s\n' "$1"
  REFUSED=$((REFUSED + 1))
}

printf 'Capture: %s\n' "${CAPTURE:-none}"
CAPTURE_HINT="run git-branch-audit.sh and pass its TipCapture: path as --capture"
if [[ -z "$CAPTURE" ]]; then
  refuse "no --capture given; a deletion batch needs the captured tips of every branch it deletes ($CAPTURE_HINT)"
elif [[ ! -f "$CAPTURE" || ! -r "$CAPTURE" ]]; then
  refuse "capture not readable: $CAPTURE ($CAPTURE_HINT)"
fi

declare -A CAP_TIP=()
declare -A CAP_TIER=()
declare -A CAP_PR=()
CAP_COMMON=""
CAP_ROWS=0
if [[ $REFUSED -eq 0 ]]; then
  first="$(head -n1 "$CAPTURE" 2>/dev/null | tr -d '\r')"
  if [[ "$first" != "# repo-hygiene branch tip capture v1" ]]; then
    refuse "not a branch tip capture (bad header): $CAPTURE ($CAPTURE_HINT)"
  else
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%$'\r'}"
      [[ -z "$line" ]] && continue
      if [[ "$line" == '#'* ]]; then
        [[ "$line" == '# common_dir: '* ]] && CAP_COMMON="${line#\# common_dir: }"
        continue
      fi
      IFS=$'\t' read -r c_branch c_tip c_tier c_pr _rest <<<"$line"
      [[ -z "$c_branch" || -z "$c_tip" ]] && continue
      CAP_TIP["$c_branch"]="$c_tip"
      CAP_TIER["$c_branch"]="${c_tier:-}"
      CAP_PR["$c_branch"]="${c_pr:-none}"
      CAP_ROWS=$((CAP_ROWS + 1))
    done <"$CAPTURE"
    if [[ $CAP_ROWS -eq 0 ]]; then
      refuse "capture holds no branch rows: $CAPTURE ($CAPTURE_HINT)"
    fi
  fi
fi

# The capture must describe THIS repository. Compared by common git dir so an
# audit run from a linked worktree and a deletion run from the main checkout
# still agree; a capture from another repository is refused outright.
COMMON_DIR="$(clean_git_common_dir "$REPO_ROOT")" || COMMON_DIR=""
if [[ $REFUSED -eq 0 && -n "$CAP_COMMON" && "$CAP_COMMON" != "unknown" ]]; then
  if [[ -z "$COMMON_DIR" || "$(clean_path_key "$CAP_COMMON")" != "$(clean_path_key "$COMMON_DIR")" ]]; then
    refuse "capture was taken in a different repository ($CAP_COMMON), not $COMMON_DIR ($CAPTURE_HINT)"
  fi
fi

# ---- Batch-wide precondition: every branch --------------------------------------

DEFAULT_BRANCH="$(clean_default_branch "$REPO_ROOT")"
CURRENT_BRANCH="$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null | tr -d '\r')"
WORKTREE_BRANCHES="$(git -C "$REPO_ROOT" worktree list --porcelain 2>/dev/null | grep '^branch' | sed 's|^branch refs/heads/||' | tr -d '\r')"

live_tip() {
  git -C "$REPO_ROOT" rev-parse --verify --quiet "refs/heads/$1" 2>/dev/null | tr -d '\r'
}

# delete_flag <tier> <pr> -> -d or -D. Mirrors §4.7: a PR-merged SAFE branch is
# squash-merged more often than not, so `-d` would refuse it; ancestry-merged
# SAFE takes the safe `-d`; LIKELY-SAFE (upstream gone) and forced REVIEW take -D.
delete_flag() {
  local tier="$1" pr="$2"
  case "$tier" in
  SAFE)
    if [[ "$pr" == *MERGED* ]]; then printf -- '-D'; else printf -- '-d'; fi
    ;;
  *) printf -- '-D' ;;
  esac
}

declare -A SEEN=()
PLAN=()
for branch in "${BRANCHES[@]}"; do
  branch="${branch%$'\r'}"
  [[ -n "${SEEN[$branch]:-}" ]] && continue
  SEEN["$branch"]=1

  if [[ "$branch" == "$CURRENT_BRANCH" ]]; then
    refuse "$branch (current branch)"
    continue
  fi
  if [[ "$branch" == "$DEFAULT_BRANCH" ]]; then
    refuse "$branch (default branch)"
    continue
  fi
  if clean_branch_matches_protected_pattern "$branch"; then
    refuse "$branch (protected pattern)"
    continue
  fi
  if grep -qxF "$branch" <<<"$WORKTREE_BRANCHES"; then
    refuse "$branch (checked out in a linked worktree; remove the worktree first)"
    continue
  fi

  tip="$(live_tip "$branch")"
  if [[ -z "$tip" ]]; then
    refuse "$branch (no such local branch)"
    continue
  fi

  [[ $REFUSED -gt 0 && $CAP_ROWS -eq 0 ]] && continue # capture itself already refused

  cap_tip="${CAP_TIP[$branch]:-}"
  if [[ -z "$cap_tip" ]]; then
    refuse "$branch (no captured tip in $CAPTURE; $CAPTURE_HINT)"
    continue
  fi
  if [[ "$cap_tip" != "$tip" ]]; then
    refuse "$branch (tip moved since capture: captured $cap_tip, now $tip; re-run git-branch-audit.sh before deleting)"
    continue
  fi

  tier="${CAP_TIER[$branch]:-}"
  case "$tier" in
  SAFE | LIKELY-SAFE) ;;
  REVIEW)
    if [[ $FORCE_REVIEW -ne 1 ]]; then
      refuse "$branch (tier REVIEW; pass --force-review only after the user confirmed the loss named in its Unpushed/Reason lines)"
      continue
    fi
    ;;
  *)
    refuse "$branch (tier ${tier:-unknown} is never deletable here)"
    continue
    ;;
  esac

  PLAN+=("$branch")
done

if [[ $REFUSED -gt 0 ]]; then
  printf 'Summary: planned=0 refused=%s deleted=0\n' "$REFUSED"
  printf 'Refused: nothing deleted; a deletion batch proceeds only when every branch in it passes\n'
  exit 3
fi

if [[ "$MODE" == "dry-run" ]]; then
  for branch in "${PLAN[@]}"; do
    printf 'Planned: %s %s (%s, git branch %s)\n' "$branch" "${CAP_TIP[$branch]}" "${CAP_TIER[$branch]}" \
      "$(delete_flag "${CAP_TIER[$branch]}" "${CAP_PR[$branch]}")"
  done
  printf 'Summary: planned=%s refused=0 deleted=0\n' "${#PLAN[@]}"
  printf 'Restore: git branch <branch> <tip> (tips in %s)\n' "$CAPTURE"
  exit 0
fi

# ---- Apply -----------------------------------------------------------------------

LEDGER="${CAPTURE%.tsv}.deleted.tsv"
BACKUP_NS="refs/repo-hygiene/deleted"
DELETED=0
FAILED=0
ABORTED=""

ledger_line() {
  printf '%s\n' "$1" >>"$LEDGER" 2>/dev/null
}

if [[ ! -f "$LEDGER" ]]; then
  if ! ledger_line "$(printf '# repo-hygiene branch deletion ledger v1\n# capture: %s\n# restore: git branch <branch> <tip>\n# columns: branch\ttip\tdeleted_at\tbackup_ref\ttier' "$CAPTURE")"; then
    printf 'Aborted: cannot write ledger %s; nothing deleted\n' "$LEDGER"
    printf 'Summary: planned=%s refused=0 deleted=0 failed=0 aborted=1\n' "${#PLAN[@]}"
    exit 1
  fi
fi

printf 'Ledger: %s\n' "$LEDGER"
printf 'BackupRefs: %s/\n' "$BACKUP_NS"

for branch in "${PLAN[@]}"; do
  tip="${CAP_TIP[$branch]}"
  tier="${CAP_TIER[$branch]}"

  # 1. Stale-plan guard, again, immediately before the destructive step.
  now_tip="$(live_tip "$branch")"
  if [[ "$now_tip" != "$tip" ]]; then
    ABORTED="$branch (tip moved between check and delete: captured $tip, now ${now_tip:-gone})"
    break
  fi

  # 2. Pin the tip so a later gc cannot prune the commits the record points at.
  if ! git -C "$REPO_ROOT" update-ref "$BACKUP_NS/$branch" "$tip" 2>/dev/null; then
    ABORTED="$branch (could not write backup ref $BACKUP_NS/$branch)"
    break
  fi

  # 3. Record the deletion durably BEFORE it happens.
  if ! ledger_line "$(printf '%s\t%s\t%s\t%s\t%s' "$branch" "$tip" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$BACKUP_NS/$branch" "$tier")"; then
    ABORTED="$branch (could not append to ledger $LEDGER)"
    break
  fi

  # 4. Delete.
  flag="$(delete_flag "$tier" "${CAP_PR[$branch]}")"
  if err="$(git -C "$REPO_ROOT" branch "$flag" "$branch" 2>&1 >/dev/null)"; then
    printf 'Deleted: %s %s (was %s) restore: git branch %s %s\n' "$branch" "$tip" "$tier" "$branch" "$tip"
    DELETED=$((DELETED + 1))
  else
    err="$(printf '%s' "$err" | tr -d '\r' | head -n1)"
    printf 'Failed: %s (%s)\n' "$branch" "${err:-git branch $flag failed}"
    FAILED=$((FAILED + 1))
  fi
done

if [[ -n "$ABORTED" ]]; then
  printf 'Aborted: %s\n' "$ABORTED"
  remaining=$((${#PLAN[@]} - DELETED - FAILED))
  printf 'Summary: planned=%s refused=0 deleted=%s failed=%s aborted=1 untouched=%s\n' \
    "${#PLAN[@]}" "$DELETED" "$FAILED" "$remaining"
  printf 'Restore: git branch <branch> <tip> (tips in %s and %s; pinned under %s/<branch>)\n' "$CAPTURE" "$LEDGER" "$BACKUP_NS"
  exit 1
fi

printf 'Summary: planned=%s refused=0 deleted=%s failed=%s\n' "${#PLAN[@]}" "$DELETED" "$FAILED"
printf 'Restore: git branch <branch> <tip> (tips in %s and %s; pinned under %s/<branch>)\n' "$CAPTURE" "$LEDGER" "$BACKUP_NS"
[[ $FAILED -eq 0 ]] || exit 1
exit 0
