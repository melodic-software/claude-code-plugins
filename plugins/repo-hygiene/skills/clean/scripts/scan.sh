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
  local category="$1" tier="$2" rel="$3" abs
  abs="$REPO_ROOT/$rel"
  [[ -e "$abs" ]] || return 0
  if clean_path_is_protected "$REPO_ROOT" "$abs"; then
    return 0
  fi
  printf 'Category: %s\n' "$category"
  printf 'Path: %s\n' "$rel"
  printf 'Size: %s\n' "$(format_size "$abs")"
  printf 'Tier: %s\n' "$tier"
  TOTAL_BYTES=$((TOTAL_BYTES + $(du -sk "$abs" 2>/dev/null | awk '{print $1}') * 1024))
}

REPO_ROOT="$(clean_repo_root)"
TOTAL_BYTES=0

if [[ -z "$REPO_ROOT" ]]; then
  echo "Error: not a git repository"
  exit 0
fi

cd "$REPO_ROOT" || exit 0

for rel in "${CLEAN_CACHE_EXPLICIT[@]}"; do
  emit_path_line "Caches" "caches" "$rel"
done

for rel in "${CLEAN_CACHE_EXPLICIT_FILES[@]}"; do
  emit_path_line "Caches" "caches" "$rel"
done

for name in "${CLEAN_CACHE_FIND_DIR_NAMES[@]}"; do
  while IFS= read -r abs; do
    [[ -z "$abs" ]] && continue
    rel="${abs#"$REPO_ROOT"/}"
    emit_path_line "Caches" "caches" "$rel"
  done < <(find "$REPO_ROOT" -type d -name "$name" \
    ! -path "$CLEAN_FIND_EXCLUDE_GIT" \
    ! -path "$CLEAN_FIND_EXCLUDE_VENV" \
    ! -path "$CLEAN_FIND_EXCLUDE_NODE_MODULES" 2>/dev/null)
done

for glob in "${CLEAN_CACHE_FIND_FILE_GLOBS[@]}"; do
  while IFS= read -r abs; do
    [[ -z "$abs" ]] && continue
    rel="${abs#"$REPO_ROOT"/}"
    emit_path_line "Caches" "caches" "$rel"
  done < <(find "$REPO_ROOT" -type f -name "$glob" \
    ! -path "$CLEAN_FIND_EXCLUDE_GIT" \
    ! -path "$CLEAN_FIND_EXCLUDE_VENV" \
    ! -path "$CLEAN_FIND_EXCLUDE_NODE_MODULES" 2>/dev/null | head -50)
done

for name in "${CLEAN_BUILD_DIR_NAMES[@]}"; do
  while IFS= read -r abs; do
    [[ -z "$abs" ]] && continue
    rel="${abs#"$REPO_ROOT"/}"
    emit_path_line "Build artifacts" "build" "$rel"
  done < <(find "$REPO_ROOT" -type d -name "$name" \
    ! -path "$CLEAN_FIND_EXCLUDE_GIT" \
    ! -path "$CLEAN_FIND_EXCLUDE_VENV" \
    ! -path "$CLEAN_FIND_EXCLUDE_NODE_MODULES" 2>/dev/null | head -100)
done

for glob in "${CLEAN_BUILD_FILE_GLOBS[@]}"; do
  while IFS= read -r abs; do
    [[ -z "$abs" ]] && continue
    rel="${abs#"$REPO_ROOT"/}"
    emit_path_line "Build artifacts" "build" "$rel"
  done < <(find "$REPO_ROOT" -type f -name "$glob" \
    ! -path "$CLEAN_FIND_EXCLUDE_GIT" \
    ! -path "$CLEAN_FIND_EXCLUDE_VENV" \
    ! -path "$CLEAN_FIND_EXCLUDE_NODE_MODULES" 2>/dev/null | head -50)
done

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
