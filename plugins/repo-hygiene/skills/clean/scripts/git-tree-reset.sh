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
#       3 blocked on default branch; 4 blocked on unpushed commits;
#       5 reset --hard failed (apply aborted before clean);
#       6 blocked on unresolvable upstream (configured but remote-tracking ref absent);
#       7 clean failed (reset succeeded; git clean -fdx errored for a reason other
#         than locked/in-use files — untracked removal is incomplete).
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

Exit: 0; 1 not a git repo; 2 usage error; 3 blocked default branch; 4 unpushed commits;
      5 reset --hard failed (apply aborted before clean);
      6 blocked on unresolvable upstream (configured but remote-tracking ref absent);
      7 clean failed (reset succeeded; git clean -fdx errored, non-locked-file cause).
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

# Gate an unresolvable upstream before any destructive op. When the upstream is
# configured (branch.<name>.remote + .merge) but its remote-tracking ref is
# absent — e.g. a feature branch whose squash-merged PR left the remote branch
# deleted and pruned — git rev-parse --abbrev-ref '@{u}' prints the LITERAL token
# @{u} instead of a ref name, and the pipe above masks git's non-zero exit, so
# the empty-guard passes and UPSTREAM=@{u}. Left unchecked, git reset --hard @{u}
# fails with "fatal: ambiguous argument '@{u}'" AFTER the guards, and (pre-#460)
# git clean -fdx would still run — a partial destructive op. Verify @{u} names a
# real, resolvable ref (a local-only upstream, branch.remote=".", still resolves
# to its local branch and passes); if not, skip the repo with a clear reason
# before any label output whose values (e.g. AheadCount) @{u} would silently
# corrupt. Never let a literal @{u} reach reset --hard.
if ! git rev-parse --verify --quiet '@{u}' >/dev/null 2>&1; then
  UNRESOLVED_REMOTE="$(git config "branch.${CURRENT_BRANCH}.remote" 2>/dev/null | tr -d '\r' || true)"
  UNRESOLVED_MERGE="$(git config "branch.${CURRENT_BRANCH}.merge" 2>/dev/null | tr -d '\r' || true)"
  UNRESOLVED_MERGE_LABEL="${UNRESOLVED_MERGE#refs/heads/}"
  printf 'Blocked: upstream-unresolved (%s/%s)\n' "${UNRESOLVED_REMOTE:-?}" "${UNRESOLVED_MERGE_LABEL:-?}"
  printf 'PlannedReset: none\n'
  printf 'PlannedClean: none\n'
  exit 6
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
# Gate the destructive clean on a successful reset. Without -e, a failed
# reset --hard would otherwise fall through to git clean -fdx, leaving the tree
# cleaned but not reset (a partial destructive op). On failure: abort before
# clean and the restore guard, report honestly, exit non-zero.
if ! git reset --hard "$UPSTREAM"; then
  printf 'FAILED: git reset --hard %s exited non-zero — aborting apply; git clean skipped. Note: reset --hard is not atomic and may have partially modified tracked files.\n' "$UPSTREAM" >&2
  printf 'AppliedReset: failed\n'
  printf 'AppliedClean: none\n'
  exit 5
fi
# Report the reset outcome as soon as it genuinely succeeds — before clean — so a
# later clean failure (exit 7 below) still surfaces the truthful AppliedReset line
# rather than swallowing it.
printf 'AppliedReset: git reset --hard %s\n' "$UPSTREAM"

# Capture clean stderr AND its exit status. git clean returns non-zero when it
# fails to remove any path; the expected, non-fatal case is a locked / in-use file
# (surfaced below as Unremovable). CLEAN_RC must be read on the very next line —
# before any other command runs — or $? is clobbered.
CLEAN_STDERR="$(git clean -fdx "${PRESERVE_ARGS[@]}" 2>&1 >/dev/null)"
CLEAN_RC=$?
UNREMOVABLE="$(printf '%s\n' "$CLEAN_STDERR" | grep -c 'failed to remove' || true)"

# Restore guard runs after clean unconditionally (data-loss guard): recover any
# tracked file clean deleted via reparse-point traversal, even on the failure path
# below — a clean that errored mid-run may still have deleted tracked files first.
RESTORED="$(clean_restore_tracked_deletions "$REPO_ROOT")"

# Gate the AppliedClean success line on the real outcome. A non-zero exit whose
# sole cause is locked/in-use files (UNREMOVABLE>0) is NOT a failure: clean ran and
# removed everything it could, and that is reported honestly as Unremovable — do
# not regress that into a hard error. Only a non-zero exit with NO 'failed to
# remove' warnings is a genuine clean failure; emit a distinct failure line and a
# non-zero exit instead of a success line that misrepresents the outcome.
# Known limitation: a non-zero exit mixing locked-file warnings AND an unrelated
# error still falls through to the success path (UNREMOVABLE>0 wins) — the locked-
# file heuristic predates this gate; a stricter classifier is deferred.
if [[ "$CLEAN_RC" -ne 0 && "${UNREMOVABLE:-0}" -eq 0 ]]; then
  printf 'FAILED: git clean -fdx exited %s (non-locked-file cause) — untracked removal incomplete; reset --hard already applied.\n' "$CLEAN_RC" >&2
  [[ -n "$CLEAN_STDERR" ]] && printf '%s\n' "$CLEAN_STDERR" >&2
  printf 'AppliedClean: failed\n'
  printf 'RestoredTracked: %s\n' "${RESTORED:-0}"
  printf 'Unremovable: %s\n' "0"
  exit 7
fi

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
