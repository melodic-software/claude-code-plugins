#!/usr/bin/env bash
# Working-tree realignment: fetch + reset --hard to upstream + clean -fdx,
# preserving secrets / local config / runtime deps / skill data by default.
#
# Usage:
#   git-tree-reset.sh [--dry-run] [--apply] [--force-default-branch]
#                     [--include-deps] [--include-secrets] [--allow-unpushed]
# Default: --dry-run
#
# Default-preserve (NOT removed unless opted in): secrets / local config
# (.env*, *.local.json/.jsonc/.md, IDE + cloud-cred + codex config), runtime
# deps (node_modules/.venv/vendor), skill data (.claude/skills/*/data/).
#   --include-deps      also remove runtime deps (rebuildable via bootstrap)
#   --include-secrets   also remove secrets / local config (UNRECOVERABLE)
# Skill data is always preserved (no flag removes it).
#
# Safety: after clean, any tracked file deleted via reparse-point traversal
# (Windows junction / Unix symlink into a tracked dir) is auto-restored from
# the index — safe because reset --hard ran first. Unpushed local commits abort
# the apply unless --allow-unpushed.
#
# Exit: 0 success; 1 not a git repo; 2 usage/validation error;
#       3 blocked on default branch; 4 blocked on unpushed commits.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/clean-common.sh
source "$SCRIPT_DIR/lib/clean-common.sh"

DRY_RUN=1
FORCE_DEFAULT=0
INCLUDE_DEPS=0
INCLUDE_SECRETS=0
ALLOW_UNPUSHED=0

usage() {
  cat <<'EOF'
git-tree-reset.sh — reset working tree to match upstream (fresh-pull semantics),
preserving secrets / local config / runtime deps / skill data by default.

Usage:
  git-tree-reset.sh [--dry-run] [--apply] [--force-default-branch]
                    [--include-deps] [--include-secrets] [--allow-unpushed] [--help]

Default: --dry-run (inventory only; no mutations).
--apply:                fetch, reset --hard to upstream, git clean -fdx (with
                        default-preserve excludes), restore reparse-point casualties.
--force-default-branch: allow run on default branch (still requires agent confirmation).
--include-deps:         also remove node_modules/.venv/vendor (rebuildable).
--include-secrets:      also remove .env*/*.local.*/IDE+cloud+codex config (UNRECOVERABLE).
--allow-unpushed:       proceed even when HEAD is ahead of upstream (discards unpushed commits).

Output labels:
  Upstream / DefaultBranch / CurrentBranch / TrackedDirty / IgnoredCount
  AheadCount: <commits HEAD is ahead of upstream>
  PreserveDeps / PreserveSecrets: <yes|no>
  PlannedReset / PlannedClean / Blocked: <reason or none>
  AppliedReset / AppliedClean (apply only)
  RestoredTracked: <count> (apply only — reparse-point casualties restored)
  Unremovable: <count> (apply only — files git clean could not delete, e.g. locked)

Exit: 0; 1 not a git repo; 2 usage error; 3 blocked default branch; 4 unpushed commits.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --dry-run) DRY_RUN=1 ;;
  --apply) DRY_RUN=0 ;;
  --force-default-branch) FORCE_DEFAULT=1 ;;
  --include-deps) INCLUDE_DEPS=1 ;;
  --include-secrets) INCLUDE_SECRETS=1 ;;
  --allow-unpushed) ALLOW_UNPUSHED=1 ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "git-tree-reset.sh: unknown arg '$1'" >&2
    exit 2
    ;;
  esac
  shift
done

REPO_ROOT="$(clean_repo_root)"
if [[ -z "$REPO_ROOT" ]]; then
  echo "git-tree-reset.sh: not a git repository" >&2
  exit 1
fi

cd "$REPO_ROOT" || exit 1

CURRENT_BRANCH="$(git branch --show-current 2>/dev/null | tr -d '\r')"
UPSTREAM="$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null | tr -d '\r' || true)"
if [[ -z "$UPSTREAM" ]]; then
  echo "git-tree-reset.sh: no upstream tracking branch (set with git push -u)" >&2
  exit 2
fi

# Fetch the remote the current branch actually tracks, not a hardcoded origin —
# a branch tracking a non-origin remote would otherwise reset to stale refs. A
# local-only upstream (branch.<name>.remote = ".") has no remote to fetch; the
# git-remote existence guard below skips the fetch in that case.
UPSTREAM_REMOTE="$(git config "branch.${CURRENT_BRANCH}.remote" 2>/dev/null | tr -d '\r' || true)"
UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-origin}"

# Resolve the default branch from the tracked remote's HEAD, not a hardcoded
# origin — a repo whose default branch lives on a non-origin remote (or is not
# named main) would otherwise slip past the default-branch guard below.
DEFAULT_BRANCH="$(git symbolic-ref "refs/remotes/${UPSTREAM_REMOTE}/HEAD" 2>/dev/null | sed "s|^refs/remotes/${UPSTREAM_REMOTE}/||" | tr -d '\r')"
if [[ -z "$DEFAULT_BRANCH" ]] && command -v gh >/dev/null 2>&1; then
  DEFAULT_BRANCH="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null | tr -d '\r')"
fi
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

TRACKED_DIRTY="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
IGNORED_COUNT="$(git status --ignored --porcelain 2>/dev/null | wc -l | tr -d ' ')"
AHEAD_COUNT="$(git rev-list --count "${UPSTREAM}..HEAD" 2>/dev/null | tr -d ' ' || echo 0)"
AHEAD_COUNT="${AHEAD_COUNT:-0}"

# Build the default-preserve exclude args once (shared by dry-run preview + apply).
mapfile -t PRESERVE_ARGS < <(clean_tree_preserve_args "$INCLUDE_DEPS" "$INCLUDE_SECRETS")

printf 'Upstream: %s\n' "$UPSTREAM"
printf 'DefaultBranch: %s\n' "$DEFAULT_BRANCH"
printf 'CurrentBranch: %s\n' "$CURRENT_BRANCH"
printf 'TrackedDirty: %s\n' "${TRACKED_DIRTY:-0}"
printf 'IgnoredCount: %s\n' "${IGNORED_COUNT:-0}"
printf 'AheadCount: %s\n' "$AHEAD_COUNT"
printf 'PreserveDeps: %s\n' "$([[ "$INCLUDE_DEPS" -eq 1 ]] && echo no || echo yes)"
printf 'PreserveSecrets: %s\n' "$([[ "$INCLUDE_SECRETS" -eq 1 ]] && echo no || echo yes)"

BLOCKED=none
if [[ "$CURRENT_BRANCH" == "$DEFAULT_BRANCH" || "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]] &&
  [[ "$FORCE_DEFAULT" -eq 0 ]]; then
  BLOCKED="default-branch (pass --force-default-branch to override)"
elif [[ "$AHEAD_COUNT" -gt 0 && "$DRY_RUN" -eq 0 && "$ALLOW_UNPUSHED" -eq 0 ]]; then
  BLOCKED="unpushed-commits ($AHEAD_COUNT ahead of $UPSTREAM — push first or pass --allow-unpushed)"
fi
printf 'Blocked: %s\n' "$BLOCKED"

if [[ "$BLOCKED" == default-branch* ]]; then
  printf 'PlannedReset: none\n'
  printf 'PlannedClean: none\n'
  exit 3
fi
if [[ "$BLOCKED" == unpushed-commits* ]]; then
  printf 'PlannedReset: none\n'
  printf 'PlannedClean: none\n'
  exit 4
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf 'PlannedFetch: git fetch %s\n' "$UPSTREAM_REMOTE"
  printf 'PlannedReset: git reset --hard %s\n' "$UPSTREAM"
  printf 'PlannedClean: git clean -fdx%s\n' "$([[ ${#PRESERVE_ARGS[@]} -gt 0 ]] && printf ' (+%d preserve excludes)' "$(((${#PRESERVE_ARGS[@]}) / 2))")"
  if [[ "$AHEAD_COUNT" -gt 0 ]]; then
    printf 'WARNING: HEAD is %s commit(s) ahead of %s — apply needs --allow-unpushed.\n' "$AHEAD_COUNT" "$UPSTREAM"
  fi
  # Dry-run is inventory-only: never fetch (it would mutate .git remote-tracking
  # refs and can prompt/fail on credentials before the user confirms anything).
  echo "--- clean preview (git clean -fdxn, default-preserve applied) ---"
  git clean -fdxn "${PRESERVE_ARGS[@]}" 2>/dev/null | head -200 || true
  exit 0
fi

if git remote get-url "$UPSTREAM_REMOTE" >/dev/null 2>&1; then
  git fetch "$UPSTREAM_REMOTE"
fi

# Re-gate unpushed commits against the just-fetched upstream. The early check
# ran against a possibly-stale tracking ref; if the upstream advanced (e.g. was
# force-pushed) the reset would otherwise discard unpushed HEAD commits without
# requiring --allow-unpushed.
AHEAD_COUNT="$(git rev-list --count "${UPSTREAM}..HEAD" 2>/dev/null | tr -d ' ' || echo 0)"
AHEAD_COUNT="${AHEAD_COUNT:-0}"
if [[ "$AHEAD_COUNT" -gt 0 && "$ALLOW_UNPUSHED" -eq 0 ]]; then
  printf 'Blocked: unpushed-commits (%s ahead of %s after fetch — push first or pass --allow-unpushed)\n' "$AHEAD_COUNT" "$UPSTREAM"
  printf 'AppliedReset: none\n'
  printf 'AppliedClean: none\n'
  exit 4
fi
git reset --hard "$UPSTREAM"

# Capture clean stderr to surface files git could not remove (locked / in use).
CLEAN_STDERR="$(git clean -fdx "${PRESERVE_ARGS[@]}" 2>&1 >/dev/null)"
UNREMOVABLE="$(printf '%s\n' "$CLEAN_STDERR" | grep -c 'failed to remove' || true)"

RESTORED="$(clean_restore_tracked_deletions "$REPO_ROOT")"

printf 'AppliedReset: git reset --hard %s\n' "$UPSTREAM"
printf 'AppliedClean: git clean -fdx%s\n' "$([[ ${#PRESERVE_ARGS[@]} -gt 0 ]] && printf ' (+%d preserve excludes)' "$(((${#PRESERVE_ARGS[@]}) / 2))")"
printf 'RestoredTracked: %s\n' "${RESTORED:-0}"
printf 'Unremovable: %s\n' "${UNREMOVABLE:-0}"

if [[ "${RESTORED:-0}" -gt 0 ]]; then
  printf 'WARNING: restored %s tracked file(s) deleted via reparse-point traversal (junction/symlink into tracked dir).\n' "$RESTORED" >&2
fi
if [[ "${UNREMOVABLE:-0}" -gt 0 ]]; then
  printf 'NOTE: %s path(s) could not be removed (locked / in use by a running process):\n' "$UNREMOVABLE" >&2
  printf '%s\n' "$CLEAN_STDERR" | grep 'failed to remove' >&2 || true
fi
exit 0
