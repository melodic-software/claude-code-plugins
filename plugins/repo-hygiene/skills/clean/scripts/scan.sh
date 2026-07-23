#!/usr/bin/env bash
# shellcheck disable=SC2154
# Read-only repo hygiene inventory for the clean scan tier.
#
# Output contract (stable labels):
#   Category: <Caches|Build artifacts|Git>
#   Path: <relative-path>
#   Size: <human size | ->
#   Tier: <caches|build|git>
#   Total reclaimable: <bytes>
#   Git worktrees: <count>
#   Git stale refs dry-run: <summary line | none>
#
# Never deletes. Exit 0 always (graceful outside git repo).
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/clean-common.sh source=lib/cleanup-paths.sh
source "$SCRIPT_DIR/lib/clean-common.sh"

usage() {
  cat <<'EOF'
scan.sh — read-only repo hygiene inventory for the clean scan tier.

Usage:
  scan.sh
  scan.sh --help

Exit: 0 (never mutates disk).
EOF
}

case "${1:-}" in
-h | --help)
  usage
  exit 0
  ;;
*) ;;
esac

format_size() {
  local p="$1"
  if [[ ! -e "$p" ]]; then
    printf '%s' '-'
    return
  fi
  du -sh "$p" 2>/dev/null | awk '{print $1}' || printf '%s' '?'
}

emit_path_line() {
  local category="$1" tier="$2" abs="$3" rel kb
  [[ -e "$abs" ]] || return 0
  if clean_path_is_protected "$REPO_ROOT" "$abs"; then
    return 0
  fi
  rel="${abs#"$REPO_ROOT"/}"
  printf 'Category: %s\n' "$category"
  printf 'Path: %s\n' "$rel"
  printf 'Size: %s\n' "$(format_size "$abs")"
  printf 'Tier: %s\n' "$tier"
  kb="$(du -sk "$abs" 2>/dev/null | awk '{print $1}')"
  TOTAL_BYTES=$((TOTAL_BYTES + ${kb:-0} * 1024))
}

REPO_ROOT="$(clean_repo_root)"
TOTAL_BYTES=0

if [[ -z "$REPO_ROOT" ]]; then
  echo "Error: not a git repository"
  exit 0
fi

cd "$REPO_ROOT" || exit 0

# Enumeration shares the single pruned-walk engine with the mutating caches/build
# tiers (clean-common.sh) so the read-only inventory and the tiers that act on it
# report the same targets from one walk that never descends .git/node_modules/.venv.
while IFS= read -r abs; do
  [[ -z "$abs" ]] && continue
  emit_path_line "Caches" "caches" "$abs"
done < <(clean_caches_candidates "$REPO_ROOT")

while IFS= read -r abs; do
  [[ -z "$abs" ]] && continue
  emit_path_line "Build artifacts" "build" "$abs"
done < <(clean_build_candidates "$REPO_ROOT")

WT_COUNT="$(git worktree list 2>/dev/null | wc -l | tr -d ' ')"
echo "Git worktrees: ${WT_COUNT:-0}"
STALE_REFS="$(git remote prune origin --dry-run 2>/dev/null | head -5 | tr '\n' '; ')"
if [[ -n "$STALE_REFS" ]]; then
  echo "Git stale refs dry-run: $STALE_REFS"
else
  echo "Git stale refs dry-run: none"
fi
echo "Tier: git"

printf 'Total reclaimable: %s\n' "$TOTAL_BYTES"
exit 0
