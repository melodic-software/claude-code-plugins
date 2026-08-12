#!/usr/bin/env bash
# Snapshot the auto-memory posture for the CURRENT project (a git repo, or the current
# directory outside one) across every settings scope.
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
scope-report.sh — snapshot auto-memory posture across settings scopes for this project.

Usage:
  scope-report.sh [--help]

Prints, for the current working directory's project (repo root, or the cwd outside a repo):
  - existence of each settings.json scope file (managed / user / project / local)
  - the live CLAUDE_CODE_DISABLE_AUTO_MEMORY environment value (if any)
  - the default auto-memory dir, its MEMORY.md line count, and topic-file count

Reads no JSON key values and never fails on a missing file or non-git dir.
EOF
  exit 0
fi

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
resolver="$script_dir/../../audit/scripts/resolve-memory-dir.sh"

# Config root: CLAUDE_CONFIG_DIR relocates the whole `~/.claude` tree (user settings
# AND the projects/ memory tree) when set — see the official .claude-directory doc.
config_root="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

exists() { [[ -f "$1" ]] && echo "PRESENT" || echo "absent"; }
dir_exists() { [[ -d "$1" ]] && echo "PRESENT" || echo "absent"; }

# Managed/policy settings locations are OS-specific and are shared vocabulary
# (lib/managed-scope.sh) rather than this script's to restate — a hand-kept copy
# here had already fallen behind the drop-in directory the settings doc adds.
# This report stays presence-only: it names the non-file surfaces (registry,
# preferences domain) without reading them, so an absent JSON file is never
# mistaken for "no managed policy deployed".
plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$script_dir/../../.." && pwd)}"
# shellcheck source=../../../lib/managed-scope.sh
source "$plugin_root/lib/managed-scope.sh"
managed="$(mscope::base_file)"
managed_dropin="$(mscope::dropin_dir)"

user_settings="$config_root/settings.json"

# Project/local scopes: anchor to the repo root when inside one, else CWD.
repo_root=$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')
base="${repo_root:-$(pwd)}"
project_settings="$base/.claude/settings.json"
local_settings="$base/.claude/settings.local.json"

echo "=== Settings scopes (precedence: managed > local > project > user) ==="
printf '%-10s %-8s %s\n' "managed" "$(exists "$managed")" "$managed"
printf '%-10s %-8s %s\n' "managed.d" "$(dir_exists "$managed_dropin")" "$managed_dropin"
while IFS= read -r policy_key; do
  [[ -n "$policy_key" ]] && printf '%-10s %-8s %s\n' "managed" "not read" "$policy_key"
done < <(mscope::registry_keys)
plist_domain="$(mscope::plist_domain)"
[[ -n "$plist_domain" ]] && printf '%-10s %-8s %s\n' "managed" "not read" "$plist_domain (managed preferences domain)"
printf '%-10s %-8s %s\n' "user" "$(exists "$user_settings")" "$user_settings"
printf '%-10s %-8s %s\n' "project" "$(exists "$project_settings")" "$project_settings"
printf '%-10s %-8s %s\n' "local" "$(exists "$local_settings")" "$local_settings"

echo
echo "=== Live environment ==="
if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
  echo "CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR} (config root relocated — user scope + memory tree live here)"
else
  echo "CLAUDE_CONFIG_DIR: unset (config root is ~/.claude)"
fi
if [[ -n "${CLAUDE_CODE_DISABLE_AUTO_MEMORY:-}" ]]; then
  echo "CLAUDE_CODE_DISABLE_AUTO_MEMORY=${CLAUDE_CODE_DISABLE_AUTO_MEMORY} (set in OS environment)"
else
  echo "CLAUDE_CODE_DISABLE_AUTO_MEMORY: unset in OS environment"
fi

echo
echo "=== Default auto-memory directory (this project) ==="
if [[ -z "$repo_root" ]]; then
  echo "Not inside a git repository — the current directory is the project key"
  echo "(memory doc: outside a git repo, the project root is used instead)."
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
  echo "MEMORY.md: absent (no auto-memory written to the default location for this project)"
fi
