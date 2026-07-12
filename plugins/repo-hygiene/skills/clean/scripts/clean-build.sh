#!/usr/bin/env bash
# shellcheck disable=SC2154
# Remove build artifacts for the clean build tier (includes caches when --include-caches).
#
# Default: --dry-run. --apply mutates. Optional dotnet clean driver when dotnet available.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/clean-common.sh source=lib/cleanup-paths.sh
source "$SCRIPT_DIR/lib/clean-common.sh"

DRY_RUN=1
INCLUDE_CACHES=0

usage() {
  cat <<'EOF'
clean-build.sh — remove build artifacts for the clean build tier.

Usage:
  clean-build.sh [--dry-run] [--apply] [--include-caches] [--help]

Default: --dry-run. --include-caches runs clean-caches.sh first.

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
  --include-caches)
    INCLUDE_CACHES=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "clean-build.sh: unknown arg '$1'" >&2
    exit 2
    ;;
  esac
done

REPO_ROOT="$(clean_repo_root)"
if [[ -z "$REPO_ROOT" ]]; then
  echo "clean-build.sh: not a git repository" >&2
  exit 1
fi

cd "$REPO_ROOT" || exit 1

CACHE_FLAG=--dry-run
[[ "$DRY_RUN" -eq 0 ]] && CACHE_FLAG=--apply

if [[ "$INCLUDE_CACHES" -eq 1 ]]; then
  bash "$SCRIPT_DIR/clean-caches.sh" "$CACHE_FLAG"
fi

# .NET clean driver — solution/project detected at runtime, never hardcoded.
# Prefer a *.slnx, then *.sln, at the repo root; skip cleanly when none exists
# or dotnet is unavailable (universal bin/obj globs below still remove output).
DOTNET_SOLUTION=""
if command -v dotnet >/dev/null 2>&1; then
  for cand in "$REPO_ROOT"/*.slnx "$REPO_ROOT"/*.sln; do
    if [[ -f "$cand" ]]; then
      DOTNET_SOLUTION="$cand"
      break
    fi
  done
fi
if [[ -n "$DOTNET_SOLUTION" ]]; then
  DOTNET_DRIVER="dotnet clean \"$DOTNET_SOLUTION\" -v q"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'Planned: %s\n' "$DOTNET_DRIVER"
  else
    if ! dotnet clean "$DOTNET_SOLUTION" -v q 2>/dev/null; then
      printf 'DRIVER_FAILED: %s\n' "$DOTNET_DRIVER" >&2
    fi
  fi
fi

plan_remove() {
  local abs="$1"
  [[ -e "$abs" ]] || return 0
  if clean_path_is_protected "$REPO_ROOT" "$abs"; then
    printf 'Skip (protected): %s\n' "${abs#"$REPO_ROOT"/}"
    return 0
  fi
  if clean_path_in_submodule "$REPO_ROOT" "$abs"; then
    printf 'Skip (submodule): %s\n' "${abs#"$REPO_ROOT"/}"
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

for name in "${CLEAN_BUILD_DIR_NAMES[@]}"; do
  while IFS= read -r abs; do
    [[ -z "$abs" ]] && continue
    plan_remove "$abs"
  done < <(find "$REPO_ROOT" -type d -name "$name" \
    ! -path "$CLEAN_FIND_EXCLUDE_GIT" \
    ! -path "$CLEAN_FIND_EXCLUDE_VENV" \
    ! -path "$CLEAN_FIND_EXCLUDE_NODE_MODULES" 2>/dev/null)
done

for glob in "${CLEAN_BUILD_FILE_GLOBS[@]}"; do
  while IFS= read -r abs; do
    [[ -z "$abs" ]] && continue
    plan_remove "$abs"
  done < <(find "$REPO_ROOT" -type f -name "$glob" \
    ! -path "$CLEAN_FIND_EXCLUDE_GIT" \
    ! -path "$CLEAN_FIND_EXCLUDE_VENV" \
    ! -path "$CLEAN_FIND_EXCLUDE_NODE_MODULES" 2>/dev/null)
done

exit 0
