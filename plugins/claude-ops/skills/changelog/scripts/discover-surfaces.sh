#!/usr/bin/env bash
# List the Claude Code surfaces a changelog decision can touch, from the repo shape.
# Marketplace: plugins/ plus .claude-plugin/marketplace.json. Anything else is a consumer.
# Exit 0 after printing the shape and every non-empty class.
set -euo pipefail

root="${1:-.}"
cd "$root"

emit() {
  local label="$1" count="$2"
  shift 2
  [[ "$count" -gt 0 ]] || return 0
  printf '%-34s %6d  %s\n' "$label" "$count" "$*"
}

count_files() {
  # shellcheck disable=SC2016
  find "$@" -type f 2>/dev/null | wc -l | tr -d ' '
}

count_dirs() {
  find "$@" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' '
}

shape="consumer"
[[ -d plugins && -f .claude-plugin/marketplace.json ]] && shape="marketplace"
echo "repo-shape: $shape"

[[ -f CLAUDE.md ]] && emit "project instructions (CLAUDE.md)" 1 CLAUDE.md
[[ -f AGENTS.md ]] && emit "project instructions (AGENTS.md)" 1 AGENTS.md
[[ -d .claude/rules ]] && emit "path-scoped rules" "$(count_files .claude/rules -name '*.md')" '.claude/rules/**/*.md'
[[ -f .claude/settings.json ]] && emit "project settings" 1 .claude/settings.json
[[ -f .mcp.json ]] && emit "mcp config" 1 .mcp.json
[[ -d .claude/hooks ]] && emit "project hooks" "$(count_files .claude/hooks)" '.claude/hooks/**'
[[ -d .claude/skills ]] && emit "project skills" "$(count_dirs .claude/skills)" '.claude/skills/*/SKILL.md'
[[ -d .claude/agents ]] && emit "project agents" "$(count_files .claude/agents -name '*.md')" '.claude/agents/*.md'

if [[ "$shape" == marketplace ]]; then
  emit "plugins" "$(count_dirs plugins)" 'plugins/*/'
  emit "plugin skills (excl. vendor)" "$(find plugins -path '*/skills/*/SKILL.md' -not -path '*/vendor/*' 2>/dev/null | wc -l | tr -d ' ')" 'plugins/*/skills/*/SKILL.md'
  emit "plugin agents" "$(find plugins -path '*/agents/*.md' 2>/dev/null | wc -l | tr -d ' ')" 'plugins/*/agents/*.md'
  emit "plugin hook dirs" "$(find plugins -mindepth 2 -maxdepth 2 -type d -name hooks 2>/dev/null | wc -l | tr -d ' ')" 'plugins/*/hooks/**'
  [[ -d docs/conventions ]] && emit "conventions" "$(count_dirs docs/conventions)" 'docs/conventions/*/README.md'
  [[ -d docs/upstream ]] && emit "upstream drift ledgers" "$(count_files docs/upstream -name '*.md')" 'docs/upstream/*.md'
fi

vend="$(find . -path '*/skills/*/vendor' -type d 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$vend" -gt 0 ]]; then
  echo "excluded: $vend vendor tree(s) under */skills/*/vendor (upstream reference material)"
fi
exit 0
