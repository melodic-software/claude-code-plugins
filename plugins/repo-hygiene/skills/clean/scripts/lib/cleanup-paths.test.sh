#!/usr/bin/env bash
# Drift contract test: cleanup-paths.sh arrays match reference/cleanup-config.md bullets.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"
# shellcheck source=cleanup-paths.sh
source "$SCRIPT_DIR/cleanup-paths.sh"

CONFIG="$(cleanup_paths_config_file)"
FAILED=0

extract_section_bullets() {
  local heading="$1"
  awk -v h="$heading" '
    $0 == h { in_section=1; next }
    in_section && /^### / { exit }
    in_section && /^## / && $0 != h { exit }
    in_section && /^- `/ {
      line = $0
      sub(/^- `/, "", line)
      sub(/` —.*/, "", line)
      sub(/`$/, "", line)
      gsub(/`\*\*\/\*\*`/, "", line)
      if (line ~ /^git /) print line
      else {
        gsub(/^\*\*\//, "", line)
        gsub(/\/\*\*$/, "", line)
        gsub(/\/$/, "", line)
        if (line != "") print line
      }
    }
  ' "$CONFIG"
}

assert_set_contains() {
  local label="$1"
  local needle="$2"
  shift 2
  local item found=1
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      found=0
      break
    fi
  done
  assert_exit "$label" 0 "$found"
}

# Key cache explicit paths from markdown
assert_set_contains "cache .pytest_cache" ".pytest_cache" "${CLEAN_CACHE_EXPLICIT[@]}"
assert_set_contains "cache .codex/logs" ".codex/logs" "${CLEAN_CACHE_EXPLICIT[@]}"
assert_set_contains "cache __pycache__ find name" "__pycache__" "${CLEAN_CACHE_FIND_DIR_NAMES[@]}"

assert_set_contains "build bin dir" "bin" "${CLEAN_BUILD_DIR_NAMES[@]}"

assert_set_contains "git worktree prune op" "git worktree prune" "${GIT_PRUNE_OPS[@]}"
assert_set_contains "git gc op" "git gc --auto --quiet" "${GIT_PRUNE_OPS[@]}"

assert_set_contains "protected branch main" "main" "${CLEAN_PROTECTED_BRANCH_EXACT[@]}"

# tree preserve SSOT — secrets/deps/skilldata arrays carry the protected classes
assert_set_contains "tree preserve .env*" ".env*" "${CLEAN_TREE_PRESERVE_SECRETS[@]}"
assert_set_contains "tree preserve *.local.json" "*.local.json" "${CLEAN_TREE_PRESERVE_SECRETS[@]}"
assert_set_contains "tree preserve *.local.jsonc" "*.local.jsonc" "${CLEAN_TREE_PRESERVE_SECRETS[@]}"
assert_set_contains "tree preserve *.local.md" "*.local.md" "${CLEAN_TREE_PRESERVE_SECRETS[@]}"
assert_set_contains "tree preserve node_modules" "node_modules/" "${CLEAN_TREE_PRESERVE_DEPS[@]}"
assert_set_contains "tree preserve .venv" ".venv/" "${CLEAN_TREE_PRESERVE_DEPS[@]}"
assert_set_contains "tree preserve vendor" "vendor/" "${CLEAN_TREE_PRESERVE_DEPS[@]}"
assert_set_contains "tree preserve skill data" ".claude/skills/*/data/" "${CLEAN_TREE_PRESERVE_SKILLDATA[@]}"

# Drift: every "Secrets / config" + "Runtime dependencies" bullet that maps to a
# gitignore pattern appears in the tree-preserve arrays (keeps SSOT aligned with
# the doc's Protected-paths classes).
ALL_TREE_PRESERVE=(
  "${CLEAN_TREE_PRESERVE_SECRETS[@]}"
  "${CLEAN_TREE_PRESERVE_SKILLDATA[@]}"
  "${CLEAN_TREE_PRESERVE_DEPS[@]}"
)
for needle in ".env*" "*.local.json" "*.local.jsonc" ".vscode/" ".aws/" "node_modules/" ".venv/" "vendor/"; do
  assert_set_contains "tree-preserve covers $needle" "$needle" "${ALL_TREE_PRESERVE[@]}"
done

# Drift: every git prune bullet in config appears in GIT_PRUNE_OPS (report-only ops excluded)
while IFS= read -r bullet; do
  [[ -z "$bullet" ]] && continue
  [[ "$bullet" == *"branch --merged"* ]] && continue
  assert_set_contains "config git op: $bullet" "$bullet" "${GIT_PRUNE_OPS[@]}"
done < <(extract_section_bullets "### git — stale-state hygiene (write-safe)" | grep '^git ')

if [[ $FAILED -ne 0 ]]; then
  echo "FAILED: $FAILED test(s)"
  exit 1
fi
echo "OK: cleanup-paths drift tests passed"
