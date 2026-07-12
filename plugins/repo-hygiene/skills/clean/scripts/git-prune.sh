#!/usr/bin/env bash
# shellcheck disable=SC2154
# Safe git prune operations for the clean git tier (§4.1).
#
# Usage:
#   git-prune.sh [--dry-run] [--apply]
# Default: --dry-run (print ops only). --apply runs GIT_PRUNE_OPS.
#
# Exit: 0 on success; 2 on usage error; 1 if not a git repo.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/clean-common.sh source=lib/cleanup-paths.sh
source "$SCRIPT_DIR/lib/clean-common.sh"

DRY_RUN=1

usage() {
  cat <<'EOF'
git-prune.sh — safe git prune ops for the clean git tier.

Usage:
  git-prune.sh [--dry-run] [--apply] [--help]

Default: --dry-run (print planned ops only).
--apply: execute git worktree prune, remote prune origin, gc --auto --quiet.

Exit: 0 success; 1 not a git repo; 2 usage error.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --dry-run)
    DRY_RUN=1
    shift
    ;;
  --apply)
    DRY_RUN=0
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "git-prune.sh: unknown arg '$1'" >&2
    exit 2
    ;;
  esac
done

REPO_ROOT="$(clean_repo_root)"
if [[ -z "$REPO_ROOT" ]]; then
  echo "git-prune.sh: not a git repository" >&2
  exit 1
fi

cd "$REPO_ROOT" || exit 1

for op in "${GIT_PRUNE_OPS[@]}"; do
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'Planned: %s\n' "$op"
  else
    printf 'Running: %s\n' "$op" >&2
    # shellcheck disable=SC2086
    eval "$op"
  fi
done

exit 0
