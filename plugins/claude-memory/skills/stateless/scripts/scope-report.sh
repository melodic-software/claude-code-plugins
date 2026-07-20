#!/usr/bin/env bash
# Snapshot the auto-memory posture for the CURRENT repo across every settings scope.
#
# Reports two deterministic things so the skill workflow doesn't hand-derive them:
#   1. Which settings.json files exist at each scope (managed / user / project / local),
#      and whether CLAUDE_CODE_DISABLE_AUTO_MEMORY is set in the live OS environment.
#   2. The DEFAULT auto-memory directory for this repo (via the plugin's single-source
#      resolver) plus its MEMORY.md line count and topic-file count.
#
# It intentionally does NOT parse the JSON key values (autoMemoryEnabled,
# autoMemoryDirectory, env.CLAUDE_CODE_DISABLE_AUTO_MEMORY): that avoids a hard `jq`
# dependency and cross-scope precedence guessing. The workflow reads the existing
# settings files (listed here) and extracts those keys with the model's own reading.
#
# autoMemoryDirectory can relocate the memory dir away from the default this script
# reports; the workflow folds any override in as an additional candidate. Windows
# managed policy can live in the registry rather than a file — flagged, not read here.
#
# Usage: bash "${CLAUDE_PLUGIN_ROOT}/skills/stateless/scripts/scope-report.sh"
# Output: a plain-text report on stdout. Never exits non-zero for a missing file or
# a non-git directory — absence is data the caller reports, not an error.

set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
scope-report.sh — snapshot auto-memory posture across settings scopes for this repo.

Usage:
  scope-report.sh [--help]

Prints, for the current working directory's repo:
  - existence of each settings.json scope file (managed / user / project / local)
  - the live CLAUDE_CODE_DISABLE_AUTO_MEMORY environment value (if any)
  - the default auto-memory dir, its MEMORY.md line count, and topic-file count

Reads no JSON key values and never fails on a missing file or non-git dir.
EOF
  exit 0
fi

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
resolver="$script_dir/../../audit/scripts/resolve-memory-dir.sh"

exists() { [[ -f "$1" ]] && echo "PRESENT" || echo "absent"; }

# Managed/policy settings location is OS-specific. Report the path for this OS so the
# workflow knows where to look; on Windows it may instead be in the registry.
case "$(uname -s 2>/dev/null || echo unknown)" in
Darwin) managed="/Library/Application Support/ClaudeCode/managed-settings.json" ;;
Linux) managed="/etc/claude-code/managed-settings.json" ;;
MINGW* | MSYS* | CYGWIN*) managed="C:/Program Files/ClaudeCode/managed-settings.json (or Windows registry: HKLM/HKCU\\SOFTWARE\\Policies\\ClaudeCode)" ;;
*) managed="(unknown OS — see settings doc for managed-settings.json location)" ;;
esac

user_settings="$HOME/.claude/settings.json"

# Project/local scopes: anchor to the repo root when inside one, else CWD.
repo_root=$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')
base="${repo_root:-$(pwd)}"
project_settings="$base/.claude/settings.json"
local_settings="$base/.claude/settings.local.json"

echo "=== Settings scopes (precedence: managed > local > project > user) ==="
managed_file="${managed%% (*}"
printf '%-10s %-8s %s\n' "managed" "$(exists "$managed_file")" "$managed"
printf '%-10s %-8s %s\n' "user" "$(exists "$user_settings")" "$user_settings"
printf '%-10s %-8s %s\n' "project" "$(exists "$project_settings")" "$project_settings"
printf '%-10s %-8s %s\n' "local" "$(exists "$local_settings")" "$local_settings"

echo
echo "=== Live environment ==="
if [[ -n "${CLAUDE_CODE_DISABLE_AUTO_MEMORY:-}" ]]; then
  echo "CLAUDE_CODE_DISABLE_AUTO_MEMORY=${CLAUDE_CODE_DISABLE_AUTO_MEMORY} (set in OS environment)"
else
  echo "CLAUDE_CODE_DISABLE_AUTO_MEMORY: unset in OS environment"
fi

echo
echo "=== Default auto-memory directory (this repo) ==="
if [[ -z "$repo_root" ]]; then
  echo "Not inside a git repository — outside a repo the project root is used as the key."
  echo "Run the skill from within the target repo, or set autoMemoryDirectory explicitly."
  exit 0
fi

mem_dir=$(bash "$resolver" 2>/dev/null | tr -d '\r')
if [[ -z "$mem_dir" ]]; then
  echo "Could not resolve the default memory dir (resolver unavailable)."
  exit 0
fi

echo "$mem_dir"
if [[ -f "$mem_dir/MEMORY.md" ]]; then
  lines=$(wc -l <"$mem_dir/MEMORY.md" | tr -d ' \r')
  topics=$(find "$mem_dir" -maxdepth 1 -name '*.md' ! -name 'MEMORY.md' 2>/dev/null | wc -l | tr -d ' \r')
  echo "MEMORY.md: PRESENT (${lines} lines); topic files: ${topics}"
else
  echo "MEMORY.md: absent (no auto-memory written to the default location for this repo)"
fi
