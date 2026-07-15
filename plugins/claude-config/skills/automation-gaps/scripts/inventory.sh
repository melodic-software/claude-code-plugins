#!/usr/bin/env bash
# Automation landscape counts for the automation-gaps skill.
#
# Output: Hook scripts, Skills, Agents, MCP servers, Plugins enabled.
# Exit: always 0.
set -u

usage() {
  cat <<'EOF'
inventory.sh — emit automation landscape counts (hooks, skills, MCP, plugins).

Usage:
  inventory.sh [--help]

Exit: always 0.
EOF
}

case "${1:-}" in
-h | --help)
  usage
  exit 0
  ;;
*) ;;
esac

# Count files matching the given find args under <dir>, or 0 when <dir> is absent.
count_files() {
  local dir="$1"
  shift
  [[ -d "$dir" ]] || {
    printf '0'
    return
  }
  find "$dir" "$@" 2>/dev/null | wc -l | tr -d ' '
}

repo_root="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
[[ -n "$repo_root" ]] && cd "$repo_root" || true

hook_scripts="$(count_files .claude/hooks -maxdepth 1 -name '*.sh')"
skills="$(count_files .claude/skills -mindepth 1 -maxdepth 1 -type d)"
agents="$(count_files .claude/agents -maxdepth 1 -name '*.md')"
mcp=0
plugins=0
if [[ -f .mcp.json ]] && command -v jq >/dev/null 2>&1; then
  mcp="$(jq '.mcpServers | length' .mcp.json 2>/dev/null || echo 0)"
fi
if [[ -f .claude/settings.json ]] && command -v jq >/dev/null 2>&1; then
  plugins="$(jq '[.enabledPlugins // {} | to_entries[] | select(.value == true)] | length' .claude/settings.json 2>/dev/null || echo 0)"
fi

printf 'Hook scripts: %s\n' "$hook_scripts"
printf 'Skills: %s\n' "$skills"
printf 'Agents: %s\n' "$agents"
printf 'MCP servers: %s\n' "$mcp"
printf 'Plugins enabled: %s\n' "$plugins"
