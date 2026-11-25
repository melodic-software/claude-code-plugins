#!/usr/bin/env bash
# Exit: 0 planned (dry-run) or every branch deleted; 1 a deletion failed or the
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/clean-common.sh source=lib/cleanup-paths.sh
source "$SCRIPT_DIR/lib/clean-common.sh"

usage() {
  cat <<'EOF'
git-branch-delete.sh - delete local branches, gated on a captured tip per branch.

Usage:
  git-branch-delete.sh --capture PATH [--dry-run] [--accept-loss] [--force-review] BRANCH...
  git-branch-delete.sh --capture PATH --apply   [--accept-loss] [--force-review] BRANCH...
  git-branch-delete.sh --help

  --capture PATH   the TipCapture: file written by git-branch-audit.sh (required)
  --dry-run        default; check every precondition and print the plan
  --apply          delete, after pinning each tip under refs/repo-hygiene/deleted/
  --accept-loss    allow LOSSY-tier branches: deletable, but their commits exist on
                   no remote ref and no tag, so the deletion loses them. Pass it
                   only after the user confirmed the audit's LossBlock as its own
                   decision, separate from the SAFE/LIKELY-SAFE confirmation.
  --force-review   allow REVIEW-tier branches (SAFE and LIKELY-SAFE need no flag;
                   PROTECTED and WORKTREE are never deletable here). Does not
                   admit LOSSY, and --accept-loss does not admit REVIEW.

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
ACCEPT_LOSS=0
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
  --accept-loss)
    ACCEPT_LOSS=1
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
    BRANCHES+=("$@")
    break
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
declare -A CAP_LANDED=()
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
      IFS=$'\t' read -r c_branch c_tip c_tier c_pr _up _ahead _behind _not_on_default c_landed _rest <<<"$line"
      if [[ -n "$c_branch" && "$c_tip" =~ ^[0-9a-f]{40,64}$ ]]; then
        CAP_TIP["$c_branch"]="$c_tip"
        CAP_TIER["$c_branch"]="$c_tier"
        CAP_PR["$c_branch"]="${c_pr:-none}"
        CAP_LANDED["$c_branch"]="$c_landed"
        CAP_ROWS=$((CAP_ROWS + 1))
      elif [[ "$line" == '# common_dir: '* ]]; then
        CAP_COMMON="${line#\# common_dir: }"
      fi
    done <"$CAPTURE"
    if [[ $CAP_ROWS -eq 0 ]]; then
      refuse "capture holds no branch rows: $CAPTURE ($CAPTURE_HINT)"
    fi
  fi
fi

COMMON_DIR="$(clean_git_common_dir "$REPO_ROOT")" || COMMON_DIR=""
if [[ $REFUSED -eq 0 ]]; then
  if [[ -z "$CAP_COMMON" || "$CAP_COMMON" == "unknown" ]]; then
    refuse "capture has no resolvable common_dir (${CAP_COMMON:-missing}); cannot verify it describes this repository ($CAPTURE_HINT)"
  elif [[ -z "$COMMON_DIR" ]]; then
    refuse "cannot resolve this repository's git common dir; cannot verify the capture describes it ($CAPTURE_HINT)"
  elif [[ "$(clean_path_key "$CAP_COMMON")" != "$(clean_path_key "$COMMON_DIR")" ]]; then
    refuse "capture was taken in a different repository ($CAP_COMMON), not $COMMON_DIR ($CAPTURE_HINT)"
  fi
fi

for op_name in MERGE_HEAD rebase-merge rebase-apply CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG; do
  op_file="$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-path "$op_name" 2>/dev/null | tr -d '\r')"
  if [[ -n "$op_file" && -e "$op_file" ]]; then
    refuse "operation in progress: $op_file; finish or abort it, then re-run git-branch-audit.sh"
    break
  fi
done

DEFAULT_BRANCH="$(clean_default_branch "$REPO_ROOT")"
CURRENT_BRANCH="$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null | tr -d '\r')"
WORKTREE_BRANCHES="$(clean_worktree_branches "$REPO_ROOT")"

live_tip() {
  git -C "$REPO_ROOT" rev-parse --verify --quiet "refs/heads/$1" 2>/dev/null | tr -d '\r'
}

PR_MERGED_RE='^#[0-9]+ MERGED( \(tip drift\))?$'
PR_OPEN_RE='^#[0-9]+ OPEN$'
LANDED_RE='^landed '

delete_mode() {
  if [[ "$1" == SAFE && ! "$2" =~ $PR_MERGED_RE ]]; then printf 'safe'; else printf 'force'; fi
}

MERGE_TARGET=""
for candidate in "refs/remotes/origin/$DEFAULT_BRANCH" "refs/heads/$DEFAULT_BRANCH" HEAD; do
  if git -C "$REPO_ROOT" rev-parse --verify --quiet "$candidate" >/dev/null 2>&1; then
    MERGE_TARGET="$candidate"
    break
  fi
done

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

  [[ $REFUSED -gt 0 && $CAP_ROWS -eq 0 ]] && continue

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
  LOSSY)
    if [[ $ACCEPT_LOSS -ne 1 ]]; then
      refuse "$branch (tier LOSSY: deleting it loses commits that exist on no remote ref and no tag; pass --accept-loss only after the user confirmed the audit's LossBlock for this branch as its own decision, separate from any SAFE/LIKELY-SAFE confirmation)"
      continue
    fi
    ;;
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

  if [[ "$(delete_mode "$tier" "${CAP_PR[$branch]}")" == safe ]] &&
    ! { [[ -n "$MERGE_TARGET" ]] && git -C "$REPO_ROOT" merge-base --is-ancestor "$tip" "$MERGE_TARGET" 2>/dev/null; }; then
    refuse "$branch (captured as SAFE by ancestry, but $tip is not merged into ${MERGE_TARGET#refs/remotes/}; the capture does not describe this branch; re-run git-branch-audit.sh)"
    continue
  fi

  if [[ "$tier" != "LOSSY" ]]; then
    live_lost=""
    if ! live_lost="$(clean_loss_count "$REPO_ROOT" "$branch")"; then
      refuse "$branch (could not count commits absent from every remote ref and tag; re-run git-branch-audit.sh before deleting)"
      continue
    fi
    if [[ "$live_lost" -gt 0 ]]; then
      pr="${CAP_PR[$branch]:-none}"
      if [[ ! "$pr" =~ $PR_OPEN_RE && ! "$pr" =~ $PR_MERGED_RE ]]; then
        has_proof=0
        [[ "$tier" == LIKELY-SAFE && "${CAP_LANDED[$branch]:-}" =~ $LANDED_RE ]] && has_proof=1
        if ! { [[ $has_proof -eq 1 ]] && clean_landed_proof "$REPO_ROOT" "$DEFAULT_BRANCH" "$branch" >/dev/null; }; then
          captured_as="$tier"
          [[ $has_proof -eq 1 ]] && captured_as+=" with a Landed proof that no longer holds"
          refuse "$branch (live reachability now loses $live_lost commits that exist on no remote ref and no tag; captured as $captured_as; re-run git-branch-audit.sh before deleting)"
          continue
        fi
      fi
    fi
  fi

  PLAN+=("$branch")
done

if [[ $REFUSED -gt 0 ]]; then
  printf 'Summary: planned=0 refused=%s deleted=0\n' "$REFUSED"
  printf 'Refused: nothing deleted; a deletion batch proceeds only when every branch in it passes\n'
  exit 3
fi

loss_note() {
  local n
  n="$(clean_loss_count "$REPO_ROOT" "$1")" || n=""
  if [[ "$n" =~ ^[0-9]+$ ]]; then
    printf ', loses %s commits only on this branch' "$n"
  else
    printf ', loses commits only on this branch (count unavailable)'
  fi
}

if [[ "$MODE" == "dry-run" ]]; then
  for branch in "${PLAN[@]}"; do
    note=""
    [[ "${CAP_TIER[$branch]}" == "LOSSY" ]] && note="$(loss_note "$branch")"
    printf 'Planned: %s %s (%s, %s delete%s)\n' "$branch" "${CAP_TIP[$branch]}" "${CAP_TIER[$branch]}" \
      "$(delete_mode "${CAP_TIER[$branch]}" "${CAP_PR[$branch]}")" "$note"
  done
  printf 'Summary: planned=%s refused=0 deleted=0\n' "${#PLAN[@]}"
  printf 'Restore: git branch <branch> <tip> (tips in %s)\n' "$CAPTURE"
  exit 0
fi

resolve_file() {
  local path="$1" target dir hops=0
  while [[ -L "$path" && $hops -lt 40 ]]; do
    target="$(readlink "$path")" || return 1
    case "$target" in
    /* | [A-Za-z]:*) path="$target" ;;
    *) path="$(dirname "$path")/$target" ;;
    esac
    hops=$((hops + 1))
  done
  dir="$(cd "$(dirname "$path")" 2>/dev/null && pwd -P)" || return 1
  printf '%s/%s' "$dir" "$(basename "$path")"
}

CAPTURE_REAL="$(resolve_file "$CAPTURE")" || CAPTURE_REAL="$CAPTURE"
LEDGER="${CAPTURE_REAL%.tsv}.deleted.tsv"
BACKUP_NS="refs/repo-hygiene/deleted"
DELETED=0
FAILED=0
ABORTED=""

ledger_line() {
  printf '%s\n' "$1" >>"$LEDGER" 2>/dev/null
}

ledger_unwritable=0
if [[ -d "$LEDGER" ]] || { [[ -e "$LEDGER" && ! -w "$LEDGER" ]]; }; then
  ledger_unwritable=1
elif [[ ! -e "$LEDGER" ]]; then
  ledger_line "$(printf '# repo-hygiene branch deletion ledger v1\n# capture: %s\n# restore: git branch <branch> <tip>\n# columns: branch\ttip\tdeleted_at\tbackup_ref\ttier' "$CAPTURE_REAL")" || ledger_unwritable=1
fi
if [[ $ledger_unwritable -eq 1 ]]; then
  printf 'Aborted: cannot write ledger %s; nothing deleted\n' "$LEDGER"
  printf 'Summary: planned=%s refused=0 deleted=0 failed=0 aborted=1\n' "${#PLAN[@]}"
  exit 1
fi

printf 'Ledger: %s\n' "$LEDGER"
printf 'BackupRefs: %s/\n' "$BACKUP_NS"

for branch in "${PLAN[@]}"; do
  tip="${CAP_TIP[$branch]}"
  tier="${CAP_TIER[$branch]}"

  now_tip="$(live_tip "$branch")"
  if [[ "$now_tip" != "$tip" ]]; then
    ABORTED="$branch (tip moved between check and delete: captured $tip, now ${now_tip:-gone})"
    break
  fi

  if ! git -C "$REPO_ROOT" update-ref "$BACKUP_NS/$branch" "$tip" 2>/dev/null; then
    ABORTED="$branch (could not write backup ref $BACKUP_NS/$branch)"
    break
  fi

  if ! ledger_line "$(printf '%s\t%s\t%s\t%s\t%s' "$branch" "$tip" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$BACKUP_NS/$branch" "$tier")"; then
    ABORTED="$branch (could not append to ledger $LEDGER)"
    break
  fi

  if err="$(git -C "$REPO_ROOT" update-ref -d "refs/heads/$branch" "$tip" 2>&1 >/dev/null)"; then
    printf 'Deleted: %s %s (was %s) restore: git branch %s %s\n' "$branch" "$tip" "$tier" "$branch" "$tip"
    DELETED=$((DELETED + 1))
  else
    now_tip="$(live_tip "$branch")"
    if [[ "$now_tip" != "$tip" ]]; then
      ledger_line "# not deleted: $branch (tip moved between pin and delete: captured $tip, now ${now_tip:-gone}; branch left intact)"
      ABORTED="$branch (tip moved between pin and delete: captured $tip, now ${now_tip:-gone}; branch left intact, pin $BACKUP_NS/$branch still records $tip)"
      break
    fi
    err="$(printf '%s' "$err" | tr -d '\r' | head -n1)"
    ledger_line "# not deleted: $branch (${err:-git update-ref -d failed})"
    printf 'Failed: %s (%s)\n' "$branch" "${err:-git update-ref -d failed}"
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
