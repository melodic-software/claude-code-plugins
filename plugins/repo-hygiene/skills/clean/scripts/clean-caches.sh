#!/usr/bin/env bash
# shellcheck disable=SC2154
# Remove tool/linter caches for the clean caches tier.
#
# Default: --dry-run (print planned removals). --apply mutates disk.
# Respects protected paths and git-tracked files.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/clean-common.sh source=lib/cleanup-paths.sh
source "$SCRIPT_DIR/lib/clean-common.sh"

DRY_RUN=1

usage() {
  cat <<'EOF'
clean-caches.sh — remove tool/linter caches for the clean caches tier.

Usage:
  clean-caches.sh [--dry-run] [--apply] [--help]

Default: --dry-run. --apply performs rm -rf on eligible targets.

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
    echo "clean-caches.sh: unknown arg '$1'" >&2
    exit 2
    ;;
  esac
done

REPO_ROOT="$(clean_repo_root)"
if [[ -z "$REPO_ROOT" ]]; then
  echo "clean-caches.sh: not a git repository" >&2
  exit 1
fi

cd "$REPO_ROOT" || exit 1

plan_remove() {
  local abs="$1"
  [[ -e "$abs" ]] || return 0
  if clean_path_is_protected "$REPO_ROOT" "$abs"; then
    printf 'Skip (protected): %s\n' "${abs#"$REPO_ROOT"/}"
    return 0
  fi
  if [[ -d "$abs" ]] && clean_dir_has_protected_descendant "$REPO_ROOT" "$abs"; then
    printf 'Skip (protected descendant): %s\n' "${abs#"$REPO_ROOT"/}"
    return 0
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'Planned remove: %s\n' "${abs#"$REPO_ROOT"/}"
  else
    rm -rf "$abs"
    printf 'Removed: %s\n' "${abs#"$REPO_ROOT"/}"
  fi
}

for rel in "${CLEAN_CACHE_EXPLICIT[@]}"; do
  plan_remove "$REPO_ROOT/$rel"
done

for rel in "${CLEAN_CACHE_EXPLICIT_FILES[@]}"; do
  plan_remove "$REPO_ROOT/$rel"
done

for name in "${CLEAN_CACHE_FIND_DIR_NAMES[@]}"; do
  while IFS= read -r abs; do
    [[ -z "$abs" ]] && continue
    plan_remove "$abs"
  done < <(find "$REPO_ROOT" -type d -name "$name" \
    ! -path "$CLEAN_FIND_EXCLUDE_GIT" \
    ! -path "$CLEAN_FIND_EXCLUDE_VENV" \
    ! -path "$CLEAN_FIND_EXCLUDE_NODE_MODULES" 2>/dev/null)
done

for glob in "${CLEAN_CACHE_FIND_FILE_GLOBS[@]}"; do
  while IFS= read -r abs; do
    [[ -z "$abs" ]] && continue
    plan_remove "$abs"
  done < <(find "$REPO_ROOT" -type f -name "$glob" \
    ! -path "$CLEAN_FIND_EXCLUDE_GIT" \
    ! -path "$CLEAN_FIND_EXCLUDE_VENV" \
    ! -path "$CLEAN_FIND_EXCLUDE_NODE_MODULES" 2>/dev/null)
done

exit 0
