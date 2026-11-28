#!/usr/bin/env bash
# Exit: 0 success; 1 target does not exist; 2 usage/validation error;
#       3 blocked (dirty / stash / worktrees / secrets); 4 unpushed work.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/clean-common.sh
source "$SCRIPT_DIR/lib/clean-common.sh"

DRY_RUN=1
ALLOW_UNPUSHED=0
INCLUDE_SECRETS=0
ROOT_OVERRIDE=""
TARGET=""

usage() {
  cat <<'EOF'
remove-path.sh — guarded removal of an orphaned clone or leftover directory
under the ghq root.

Usage:
  remove-path.sh <target> [--dry-run] [--apply] [--allow-unpushed]
                 [--include-secrets] [--root <dir>] [--help]

Default: --dry-run (print guard results and the planned removal only).
--apply:           execute the removal after all guards pass.
--allow-unpushed:  proceed despite unpushed branches or a detached HEAD.
--include-secrets: proceed despite ignored secret-class files (UNRECOVERABLE).
--root <dir>:      containment root (default: ghq root).

Output labels:
  Target / Root / Kind: <repo|bare-repo|dir>
  TrackedDirty / StashCount / WorktreeCount / UnpushedRefs / SecretsCount / SkillData
  Blocked: <reason or none>
  Planned / Applied: rm -rf <target>

Exit: 0 success; 1 target missing; 2 usage/validation; 3 blocked; 4 unpushed.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --dry-run) DRY_RUN=1 ;;
  --apply) DRY_RUN=0 ;;
  --allow-unpushed) ALLOW_UNPUSHED=1 ;;
  --include-secrets) INCLUDE_SECRETS=1 ;;
  --root)
    shift
    [[ $# -gt 0 ]] || {
      echo "remove-path.sh: --root needs a value" >&2
      exit 2
    }
    ROOT_OVERRIDE="$1"
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  -*)
    echo "remove-path.sh: unknown arg '$1'" >&2
    exit 2
    ;;
  *)
    [[ -z "$TARGET" ]] || {
      echo "remove-path.sh: multiple targets given" >&2
      exit 2
    }
    TARGET="$1"
    ;;
  esac
  shift
done

if [[ -z "$TARGET" ]]; then
  echo "remove-path.sh: no target given" >&2
  exit 2
fi

ROOT="$ROOT_OVERRIDE"
if [[ -z "$ROOT" ]]; then
  ROOT="$(git config ghq.root 2>/dev/null | tr -d '\r')"
fi
if [[ -z "$ROOT" ]] && command -v ghq >/dev/null 2>&1; then
  ROOT="$(ghq root 2>/dev/null | tr -d '\r')"
fi
if [[ -z "$ROOT" ]]; then
  echo "remove-path.sh: no containment root (no ghq root; pass --root)" >&2
  exit 2
fi

norm() {
  local p
  p="$(cd "$1" 2>/dev/null && pwd -P)" || return 1
  printf '%s' "${p//\\//}"
}

if clean_path_is_reparse_point "$TARGET"; then
  echo "remove-path.sh: target is a symlink/reparse point — refusing" >&2
  exit 2
fi
if [[ ! -d "$TARGET" ]]; then
  echo "remove-path.sh: target does not exist: $TARGET" >&2
  exit 1
fi

ROOT_ABS="$(norm "$ROOT")" || {
  echo "remove-path.sh: root does not exist: $ROOT" >&2
  exit 2
}
TARGET_ABS="$(norm "$TARGET")" || exit 1

if [[ "$TARGET_ABS" == "$ROOT_ABS" ]]; then
  echo "remove-path.sh: target is the containment root itself — refusing" >&2
  exit 2
fi
if [[ "$TARGET_ABS" != "$ROOT_ABS"/* ]]; then
  echo "remove-path.sh: target is outside the containment root ($ROOT_ABS)" >&2
  exit 2
fi

dev_of() { stat -c '%d' "$1" 2>/dev/null || stat -f '%d' "$1" 2>/dev/null; }
root_dev="$(dev_of "$ROOT_ABS")"
target_dev="$(dev_of "$TARGET_ABS")"
if [[ -n "$root_dev" && -n "$target_dev" && "$root_dev" != "$target_dev" ]]; then
  echo "remove-path.sh: target is on a different filesystem/mount than the root — refusing" >&2
  exit 2
fi

if [[ -f "$TARGET_ABS/.git" ]]; then
  echo "remove-path.sh: target is a linked worktree — use git worktree remove" >&2
  exit 2
fi

KIND=dir
TRACKED_DIRTY=0
STASH_COUNT=0
WORKTREE_COUNT=0
UNPUSHED_REFS=0
SECRETS_COUNT=0
SKILLDATA_COUNT=0

count_preserve_classes() {
  clean_path_matches_secret_class "$1" && SECRETS_COUNT=$((SECRETS_COUNT + 1))
  clean_path_matches_skilldata "$1" && SKILLDATA_COUNT=$((SKILLDATA_COUNT + 1))
}

if [[ -f "$TARGET_ABS/HEAD" && -d "$TARGET_ABS/objects" && -d "$TARGET_ABS/refs" ]]; then
  KIND=bare-repo
elif [[ -d "$TARGET_ABS/.git" ]]; then
  KIND=repo
fi

if [[ "$KIND" == dir ]]; then
  nested="$(find "$TARGET_ABS" -mindepth 2 -name .git -print -quit 2>/dev/null)"
  if [[ -z "$nested" ]]; then
    while IFS= read -r -d '' head_file; do
      d="${head_file%/HEAD}"
      if [[ -d "$d/objects" && -d "$d/refs" ]]; then
        nested="$d"
        break
      fi
    done < <(find "$TARGET_ABS" -mindepth 2 -name HEAD -type f -print0 2>/dev/null)
  fi
  if [[ -n "$nested" ]]; then
    echo "remove-path.sh: target contains nested git repos — inspect and remove them individually first" >&2
    exit 2
  fi
fi

if [[ "$KIND" != dir ]]; then
  if [[ "$KIND" == repo ]]; then
    if ! dirty_out="$(git -C "$TARGET_ABS" status --porcelain --untracked-files=all 2>/dev/null)"; then
      echo "remove-path.sh: cannot inspect repo state — refusing" >&2
      exit 2
    fi
    [[ -n "$dirty_out" ]] && TRACKED_DIRTY="$(printf '%s\n' "$dirty_out" | wc -l | tr -d ' ')"
    if ! stash_out="$(git -C "$TARGET_ABS" stash list 2>/dev/null)"; then
      echo "remove-path.sh: cannot inspect stash state — refusing" >&2
      exit 2
    fi
    [[ -n "$stash_out" ]] && STASH_COUNT="$(printf '%s\n' "$stash_out" | wc -l | tr -d ' ')"

    while IFS= read -r ignored; do
      [[ -z "$ignored" ]] && continue
      count_preserve_classes "$ignored"
    done < <(git -C "$TARGET_ABS" ls-files --others --ignored --exclude-standard 2>/dev/null | tr -d '\r')
  fi

  if ! wt_out="$(git -C "$TARGET_ABS" worktree list --porcelain 2>/dev/null)"; then
    echo "remove-path.sh: cannot inspect worktree state — refusing" >&2
    exit 2
  fi
  WORKTREE_COUNT="$(printf '%s\n' "$wt_out" | grep -c '^worktree ' || true)"

  while IFS=' ' read -r ref upstream; do
    [[ -z "$ref" ]] && continue
    if [[ -z "$upstream" ]]; then
      UNPUSHED_REFS=$((UNPUSHED_REFS + 1))
      continue
    fi
    if ! ahead="$(git -C "$TARGET_ABS" rev-list --count "$upstream..$ref" 2>/dev/null | tr -d ' ')" || [[ -z "$ahead" ]]; then
      UNPUSHED_REFS=$((UNPUSHED_REFS + 1))
      continue
    fi
    [[ "$ahead" -gt 0 ]] && UNPUSHED_REFS=$((UNPUSHED_REFS + 1))
  done < <({
    git -C "$TARGET_ABS" for-each-ref refs/heads --format='%(refname:short) %(upstream:short)' 2>/dev/null
    git -C "$TARGET_ABS" for-each-ref refs/tags --format='%(refname:short) %(upstream:short)' 2>/dev/null
  } | tr -d '\r')

  if [[ "$KIND" == repo ]] &&
    [[ -z "$(git -C "$TARGET_ABS" branch --show-current 2>/dev/null | tr -d '\r')" ]] &&
    git -C "$TARGET_ABS" rev-parse -q --verify HEAD >/dev/null 2>&1; then
    UNPUSHED_REFS=$((UNPUSHED_REFS + 1))
  fi
else
  while IFS= read -r -d '' f; do
    count_preserve_classes "${f#"$TARGET_ABS"/}"
  done < <(find "$TARGET_ABS" -mindepth 1 -print0 2>/dev/null)
fi

printf 'Target: %s\n' "$TARGET_ABS"
printf 'Root: %s\n' "$ROOT_ABS"
printf 'Kind: %s\n' "$KIND"
printf 'TrackedDirty: %s\n' "$TRACKED_DIRTY"
printf 'StashCount: %s\n' "$STASH_COUNT"
printf 'WorktreeCount: %s\n' "$WORKTREE_COUNT"
printf 'UnpushedRefs: %s\n' "$UNPUSHED_REFS"
printf 'SecretsCount: %s\n' "$SECRETS_COUNT"
printf 'SkillData: %s\n' "$SKILLDATA_COUNT"

BLOCKED=none
EXIT=0
if [[ "$TRACKED_DIRTY" -gt 0 ]]; then
  BLOCKED="dirty ($TRACKED_DIRTY uncommitted change(s))"
  EXIT=3
elif [[ "$STASH_COUNT" -gt 0 ]]; then
  BLOCKED="stash ($STASH_COUNT entry(ies))"
  EXIT=3
elif [[ "$WORKTREE_COUNT" -gt 1 ]]; then
  BLOCKED="linked-worktrees ($((WORKTREE_COUNT - 1)) registered — remove them first)"
  EXIT=3
elif [[ "$SKILLDATA_COUNT" -gt 0 ]]; then
  BLOCKED="skill-data ($SKILLDATA_COUNT skill-owned data file(s) — irreplaceable; move them out first, no override)"
  EXIT=3
elif [[ "$SECRETS_COUNT" -gt 0 && "$INCLUDE_SECRETS" -eq 0 ]]; then
  BLOCKED="secrets ($SECRETS_COUNT ignored secret-class file(s) — pass --include-secrets to discard)"
  EXIT=3
elif [[ "$UNPUSHED_REFS" -gt 0 && "$ALLOW_UNPUSHED" -eq 0 ]]; then
  BLOCKED="unpushed ($UNPUSHED_REFS ref(s) with unpushed work — pass --allow-unpushed to discard)"
  EXIT=4
fi
printf 'Blocked: %s\n' "$BLOCKED"

if [[ "$BLOCKED" != none ]]; then
  printf 'Planned: none\n'
  exit "$EXIT"
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf 'Planned: rm -rf %s\n' "$TARGET_ABS"
  exit 0
fi

rm_flags=(-rf)
if grep -qi coreutils < <(rm --version 2>/dev/null); then
  rm_flags+=(--one-file-system)
elif rm -f -x "$TARGET_ABS.__onefs_probe__" 2>/dev/null; then
  rm_flags+=(-x)
fi
rm "${rm_flags[@]}" "$TARGET_ABS"
if [[ -e "$TARGET_ABS" ]]; then
  echo "remove-path.sh: removal incomplete (locked / in use / crosses a mount): $TARGET_ABS" >&2
  exit 1
fi
printf 'Applied: rm -rf %s\n' "$TARGET_ABS"
exit 0
