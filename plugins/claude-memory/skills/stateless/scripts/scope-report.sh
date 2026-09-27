#!/usr/bin/env bash
# Snapshot the auto-memory posture for the CURRENT project (a git repo, or the current
# directory outside one) across every settings scope.
#
# Reads no JSON key values, avoiding a jq dependency and precedence guessing; the
# workflow reads the listed files and folds in any autoMemoryDirectory relocation.

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

config_root="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

exists() { [[ -f "$1" ]] && echo "PRESENT" || echo "absent"; }
dir_exists() { [[ -d "$1" ]] && echo "PRESENT" || echo "absent"; }

row() { printf '%-10s %-8s %s\n' "$1" "$2" "$3"; }

# Presence-only: non-file policy surfaces are named, never read, so an absent JSON
# file is never mistaken for "no managed policy deployed".
plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$script_dir/../../.." && pwd)}"
# shellcheck source=../../../lib/managed-scope.sh
source "$plugin_root/lib/managed-scope.sh"
# The topic-file counting rule is shared with the sibling enumerate-all-projects.sh,
# whose printed count is a contract of its own.
# shellcheck source=../../../lib/topic-count.sh
source "$plugin_root/lib/topic-count.sh"
managed="$(mscope::base_file)"
managed_dropin="$(mscope::dropin_dir)"

user_settings="$config_root/settings.json"

repo_root=$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')
base="${repo_root:-$(pwd)}"
project_settings="$base/.claude/settings.json"
local_settings="$base/.claude/settings.local.json"

echo "=== Settings scopes (precedence: managed > local > project > user) ==="
row "managed" "$(exists "$managed")" "$managed"
row "managed.d" "$(dir_exists "$managed_dropin")" "$managed_dropin"
while IFS= read -r policy_key; do
  [[ -n "$policy_key" ]] && row "managed" "not read" "$policy_key"
done < <(mscope::registry_keys)
plist_domain="$(mscope::plist_domain)"
[[ -n "$plist_domain" ]] && row "managed" "not read" "$plist_domain (managed preferences domain)"
row "user" "$(exists "$user_settings")" "$user_settings"
row "project" "$(exists "$project_settings")" "$project_settings"
row "local" "$(exists "$local_settings")" "$local_settings"

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
  topics=$(mtopics::count "$mem_dir")
  echo "MEMORY.md: PRESENT (${lines} lines); topic files: ${topics}"
else
  echo "MEMORY.md: absent (no auto-memory written to the default location for this project)"
fi
