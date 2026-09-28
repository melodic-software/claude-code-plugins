#!/usr/bin/env bash
# Dry-run inventory of linked worktrees and proposed actions.
#
# This script never deletes a worktree, a branch, a stash, a drive-root directory, or a file. Every
# Proposed: line is a label for a person to read. Squash-merge repositories
# cannot use merge-base --is-ancestor against main: a merged branch is not an
# ancestor of main. review-remove is proposed only when the worktree is clean,
# unlocked, not a main checkout, has a MERGED pull request, and its HEAD matches
# the remote branch tip (or the remote branch is already gone and HEAD matches
# the pull request's head oid).
#
# Usage:
#   worktree-reconcile.sh [--repo DIR] [--hold SUBSTR]... [--limit N] [--drive-root DIR]
#   worktree-reconcile.sh --help
#   worktree-reconcile.sh --apply   # refused; exit 2
#
# Exit: 0 report written; 2 usage error or not a git repository.
set -uo pipefail

usage() {
  sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

REPO=""
HOLDS=()
DRIVE_ROOT=""
LIMIT="${CLEAN_PR_LIST_LIMIT:-1000}"

while [[ $# -gt 0 ]]; do
  case "$1" in
  --repo)
    [[ $# -ge 2 ]] || {
      echo "worktree-reconcile.sh: --repo requires a directory" >&2
      exit 2
    }
    REPO="$2"
    shift
    ;;
  --hold)
    [[ $# -ge 2 ]] || {
      echo "worktree-reconcile.sh: --hold requires a substring" >&2
      exit 2
    }
    HOLDS+=("$2")
    shift
    ;;
  --limit)
    [[ $# -ge 2 ]] || {
      echo "worktree-reconcile.sh: --limit requires a number" >&2
      exit 2
    }
    LIMIT="$2"
    shift
    ;;
  --drive-root)
    [[ $# -ge 2 ]] || {
      echo "worktree-reconcile.sh: --drive-root requires a directory" >&2
      exit 2
    }
    DRIVE_ROOT="$2"
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --apply)
    echo "worktree-reconcile.sh: --apply is refused. This command only prints a dry-run report." >&2
    exit 2
    ;;
  *)
    echo "worktree-reconcile.sh: unknown arg '$1'" >&2
    exit 2
    ;;
  esac
  shift
done

if [[ -z "$REPO" ]]; then
  REPO="$(pwd)"
fi
if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "worktree-reconcile.sh: not a git repository: $REPO" >&2
  exit 2
fi
REPO="$(git -C "$REPO" rev-parse --show-toplevel)"
if [[ -n "$DRIVE_ROOT" && ! -d "$DRIVE_ROOT" ]]; then
  echo "worktree-reconcile.sh: --drive-root is not a directory: $DRIVE_ROOT" >&2
  exit 2
fi

declare -a WT_PATH=() WT_HEAD=() WT_BRANCH=() WT_LOCKED=()

flush_record() {
  [[ -n "${cur_path:-}" ]] || return 0
  WT_PATH+=("$cur_path")
  WT_HEAD+=("${cur_head:-}")
  WT_BRANCH+=("${cur_branch:-}")
  WT_LOCKED+=("${cur_locked:-no}")
  cur_path=""
  cur_head=""
  cur_branch=""
  cur_locked="no"
}

cur_path=""
cur_head=""
cur_branch=""
cur_locked="no"
while IFS= read -r line || [[ -n "$line" ]]; do
  case "$line" in
  worktree\ *)
    flush_record
    cur_path="${line#worktree }"
    ;;
  HEAD\ *)
    cur_head="${line#HEAD }"
    ;;
  branch\ *)
    cur_branch="${line#branch }"
    ;;
  detached)
    cur_branch=""
    ;;
  locked*)
    cur_locked="yes"
    ;;
  "")
    flush_record
    ;;
  *) ;;
  esac
done < <(git -C "$REPO" worktree list --porcelain)
flush_record

# Pull-request map. Missing gh or jq is announced; it is not an empty map.
PR_STATUS="PRDataUnavailable: gh or jq not on PATH"
declare -A PR_STATE=() PR_OID=()
pr_raw=""
if command -v gh >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  pr_raw="$(cd "$REPO" && gh pr list --state all --json headRefName,state,headRefOid --limit "$LIMIT" 2>/dev/null || true)"
  if [[ -z "$pr_raw" ]] || ! printf '%s' "$pr_raw" | jq -e 'type == "array"' >/dev/null 2>&1; then
    PR_STATUS="PRDataUnavailable: gh pr list failed or returned nothing jq could parse"
  else
    pr_count="$(printf '%s' "$pr_raw" | jq 'length')"
    PR_STATUS="PRCount: $pr_count"
    if [[ "$pr_count" -ge "$LIMIT" ]]; then
      PR_STATUS="$PR_STATUS"$'\n'"PRDataTruncated: gh pr list returned $pr_count rows at --limit $LIMIT"
    fi
    while IFS=$'\t' read -r name state oid; do
      [[ -n "$name" ]] || continue
      # First row wins. gh returns newest first, which is the row to trust.
      if [[ -z "${PR_STATE[$name]:-}" ]]; then
        PR_STATE["$name"]="$state"
        PR_OID["$name"]="$oid"
      fi
    done < <(printf '%s' "$pr_raw" | jq -r '.[] | [.headRefName, .state, .headRefOid] | @tsv')
  fi
fi

hold_match() {
  local path="$1" needle
  for needle in "${HOLDS[@]+"${HOLDS[@]}"}"; do
    if [[ "$path" == *"$needle"* ]]; then
      printf '%s' "$needle"
      return 0
    fi
  done
  return 1
}

# Names from the fleet-reconcile record. A bare run protects them without
# --hold. Matching is the path basename or the branch short name.
builtin_hold() {
  local path="$1" short="$2" base
  base="$(basename "$path")"
  case "$base" in
  _vfy | ccp-2840-fix | ccp-2840 | silent-revert-markers | spike | ccp-2590-engine)
    printf '%s' "$base"
    return 0
    ;;
  *) ;;
  esac
  case "$short" in
  fix/2648-tzdata-degradation | fix-2618-belt-run-scoped-lifetime | *-main)
    printf '%s' "$short"
    return 0
    ;;
  *) ;;
  esac
  return 1
}

branch_short() {
  local ref="$1"
  printf '%s' "${ref#refs/heads/}"
}

printf 'WorktreeReconcile: dry-run\n'
printf 'Repo: %s\n' "$REPO"
printf '%s\n' "$PR_STATUS"

stash_n=0
while IFS= read -r stash_line; do
  [[ -n "$stash_line" ]] || continue
  stash_n=$((stash_n + 1))
  printf 'Stash: %s\n' "${stash_line%%$'\t'*}"
  printf 'StashSubject: %s\n' "${stash_line#*$'\t'}"
  printf 'Proposed: inspect-before-prune\n'
done < <(git -C "$REPO" stash list --format '%gd%x09%s')
printf 'Stashes: %s\n' "$stash_n"

holds=0
reviews=0
for ((i = 0; i < ${#WT_PATH[@]}; i++)); do
  path="${WT_PATH[$i]}"
  head="${WT_HEAD[$i]}"
  branch="${WT_BRANCH[$i]}"
  locked="${WT_LOCKED[$i]}"
  short="$(branch_short "$branch")"
  dirty="no"
  merge="no"
  if [[ -d "$path" ]]; then
    if [[ -n "$(git -C "$path" status --porcelain 2>/dev/null || true)" ]]; then
      dirty="yes"
    fi
    if [[ -e "$path/.git" ]] && git -C "$path" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
      merge="yes"
    fi
    # A linked worktree's .git is a file. MERGE_HEAD still resolves through it.
    if git -C "$path" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
      merge="yes"
    fi
  else
    dirty="missing"
  fi

  proposed="hold-insufficient-evidence"
  reason="pull-request map or remote tip could not prove the work landed"
  if needle="$(hold_match "$path")"; then
    proposed="hold-carve-out"
    reason="path matches --hold $needle"
  elif needle="$(builtin_hold "$path" "$short")"; then
    proposed="hold-carve-out"
    reason="built-in carve-out $needle"
  elif [[ "$i" -eq 0 ]]; then
    proposed="hold-primary"
    reason="primary worktree; this report never proposes removing it"
  elif [[ "$locked" == yes ]]; then
    proposed="hold-locked"
    reason="worktree is locked"
  elif [[ "$merge" == yes ]]; then
    proposed="hold-merge"
    reason="merge in progress"
  elif [[ "$dirty" == yes || "$dirty" == missing ]]; then
    proposed="hold-dirty"
    reason="uncommitted work or the worktree directory is missing"
  elif [[ "$short" == main || "$short" == master || "$path" == *-main ]]; then
    proposed="hold-main"
    reason="main checkout or a *-main worktree path"
  elif [[ -n "$short" && "${PR_STATE[$short]:-}" == OPEN ]]; then
    proposed="hold-open-pr"
    reason="branch has an open pull request"
  elif [[ -n "$short" && "${PR_STATE[$short]:-}" == MERGED && -n "$head" ]]; then
    remote_sha="$(git -C "$REPO" ls-remote origin "refs/heads/$short" 2>/dev/null | awk 'NR==1 {print $1}')"
    pr_oid="${PR_OID[$short]:-}"
    if [[ -n "$remote_sha" && "$remote_sha" == "$head" ]]; then
      proposed="review-remove"
      reason="clean worktree, MERGED pull request, HEAD matches origin/$short"
    elif [[ -z "$remote_sha" && -n "$pr_oid" && "$pr_oid" == "$head" ]]; then
      proposed="review-remove"
      reason="clean worktree, MERGED pull request, remote branch is gone, HEAD matches the pull request head"
    elif [[ -n "$remote_sha" && "$remote_sha" != "$head" ]]; then
      proposed="hold-sha-mismatch"
      reason="HEAD does not match origin/$short, so later work may be unpushed"
    else
      proposed="hold-insufficient-evidence"
      reason="MERGED pull request but the remote tip could not be compared"
    fi
  elif [[ -n "$short" && -z "${PR_STATE[$short]:-}" && "$PR_STATUS" == PRCount:* ]]; then
    proposed="hold-no-merged-pr"
    reason="no pull request row for this branch; squash-merge detection did not fire"
  fi

  printf 'Worktree: %s\n' "$path"
  printf 'Branch: %s\n' "${short:-detached}"
  printf 'Head: %s\n' "$head"
  printf 'Dirty: %s\n' "$dirty"
  printf 'Locked: %s\n' "$locked"
  printf 'Proposed: %s\n' "$proposed"
  printf 'Reason: %s\n' "$reason"
  case "$proposed" in
  review-remove) reviews=$((reviews + 1)) ;;
  *) holds=$((holds + 1)) ;;
  esac
done

printf 'Summary: worktrees=%s hold=%s review-remove=%s\n' "${#WT_PATH[@]}" "$holds" "$reviews"

# Filed drive-root names from #2931. The directory that holds them is host-specific,
# so a run with no --drive-root prints the proposed actions and does not scan.
# Present/Entries are observations. Proposed is the filed action. Nothing is deleted.
if [[ -n "$DRIVE_ROOT" ]]; then
  printf 'DriveStrays: scanned\n'
  printf 'DriveRoot: %s\n' "$DRIVE_ROOT"
else
  printf 'DriveStrays: filed-record\n'
  printf 'DriveRoot: unset\n'
  printf 'Note: drive-root paths are host-specific. Pass --drive-root to scan one directory. This run did not scan a drive.\n'
fi
while IFS=$'\t' read -r stray_name stray_proposed stray_reason; do
  [[ -n "$stray_name" ]] || continue
  printf 'Stray: %s\n' "$stray_name"
  stray_entries=""
  if [[ -z "$DRIVE_ROOT" ]]; then
    stray_present="not-scanned"
  else
    stray_path="$DRIVE_ROOT/$stray_name"
    if [[ -d "$stray_path" ]]; then
      stray_present="yes"
      stray_entries="$(find "$stray_path" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d '[:space:]')"
    elif [[ -e "$stray_path" ]]; then
      stray_present="not-a-directory"
    else
      stray_present="no"
    fi
  fi
  printf 'Present: %s\n' "$stray_present"
  if [[ -n "$stray_entries" ]]; then
    printf 'Entries: %s\n' "$stray_entries"
  fi
  printf 'Proposed: %s\n' "$stray_proposed"
  printf 'Reason: %s\n' "$stray_reason"
done <<'EOF'
lane-j-mut-base	review-delete	Filed in #2931: no unique data, and the owner handoff calls the directory disposable. This report does not delete it.
lane-j-mut-mainbase	review-delete	Filed in #2931: no unique data, and the owner handoff calls the directory disposable. This report does not delete it.
lane-v157-ext	hold-until-verdict	Filed in #2931: hold until proxy pull request 157 has a verdict.
lane-v159-mut	hold-until-verdict	Filed in #2931: hold until proxy pull request 159 is verified.
lane-v159-repro	hold-until-verdict	Filed in #2931: hold until proxy pull request 159 is verified.
spike	hold-operator-deliverable	Filed in #2931: operator deliverable. Do not delete.
EOF
printf 'DriveStrayNote: inventory only; no drive-root directory or file was deleted\n'
printf 'Note: dry-run only; no worktree, branch, stash, drive-root directory, or file was deleted\n'
exit 0
