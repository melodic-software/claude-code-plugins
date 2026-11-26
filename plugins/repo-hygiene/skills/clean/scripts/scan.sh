#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/clean-common.sh
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

emit_tier() {
  local category="$1" tier="$2" abs kb
  while IFS= read -r abs; do
    [[ -e "$abs" ]] || continue
    clean_path_is_protected "$REPO_ROOT" "$abs" && continue
    printf 'Category: %s\n' "$category"
    printf 'Path: %s\n' "${abs#"$REPO_ROOT"/}"
    printf 'Size: %s\n' "$(du -sh "$abs" 2>/dev/null | awk '{print $1}' || printf '%s' '?')"
    printf 'Tier: %s\n' "$tier"
    kb="$(du -sk "$abs" 2>/dev/null | awk '{print $1}')"
    TOTAL_BYTES=$((TOTAL_BYTES + ${kb:-0} * 1024))
  done
}

REPO_ROOT="$(clean_repo_root)"
TOTAL_BYTES=0

if [[ -z "$REPO_ROOT" ]]; then
  echo "Error: not a git repository"
  exit 0
fi

cd "$REPO_ROOT" || exit 0

emit_tier "Caches" "caches" < <(clean_caches_candidates "$REPO_ROOT")
emit_tier "Build artifacts" "build" < <(clean_build_candidates "$REPO_ROOT")

WT_COUNT="$(git worktree list 2>/dev/null | wc -l | tr -d ' ')"
echo "Git worktrees: ${WT_COUNT:-0}"
echo "Git stale refs dry-run: remote prune not measured"
echo "Tier: git"

printf 'Total reclaimable: %s\n' "$TOTAL_BYTES"
exit 0
