#!/usr/bin/env bash
# Discover the Claude Code surfaces a changelog item can touch, from the repo shape.
#
# Usage: discover-surfaces.sh [ROOT]
#
# Prints "repo-shape: marketplace|consumer", then one line per present surface
# class with its count and glob. A marketplace repo has plugins/ and
# .claude-plugin/marketplace.json; anything else is a consumer. Vendored upstream
# docs (*/skills/*/vendor) are not counted; the last line says how many trees were
# skipped. Exits 0 whenever ROOT exists, 2 for a missing ROOT or an unknown argument.
set -euo pipefail

if [[ "$#" -gt 1 ]] || case "${1:-}" in -*) true ;; *) false ;; esac; then
  echo "discover-surfaces: unknown argument: $*" >&2
  exit 2
fi
root="${1:-.}"
cd "$root" 2>/dev/null || { echo "discover-surfaces: no such directory: $root" >&2; exit 2; }

emit() {
  local label="$1" count="$2"
  shift 2
  if [[ "$count" -gt 0 ]]; then printf '%-36s %6d  %s\n' "$label" "$count" "$*"; fi
  return 0
}
count_lines() { wc -l | tr -d ' '; }
count_files() { find "$@" -type f 2>/dev/null | count_lines; }
count_dirs() { find "$@" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | count_lines; }
# emit_file LABEL PATH: one line when PATH is a regular file.
emit_file() { if [[ -f "$2" ]]; then emit "$1" 1 "$2"; fi; return 0; }
# emit_tree LABEL DIR GLOB FIND-ARGS...: count files under DIR when it exists.
emit_tree() {
  local label="$1" dir="$2" glob="$3"
  shift 3
  if [[ -d "$dir" ]]; then emit "$label" "$(count_files "$dir" "$@")" "$glob"; fi
  return 0
}

shape=consumer
if [[ -d plugins ]] && [[ -f .claude-plugin/marketplace.json ]]; then shape=marketplace; fi
echo "repo-shape: $shape"

emit_file "project instructions (CLAUDE.md)" CLAUDE.md
emit_file "project instructions (AGENTS.md)" AGENTS.md
emit_file "local instructions (CLAUDE.local.md)" CLAUDE.local.md
emit_tree "path-scoped rules" .claude/rules '.claude/rules/**/*.md' -name '*.md'
emit_file "project settings" .claude/settings.json
emit_file "local settings" .claude/settings.local.json
emit_file "mcp config" .mcp.json
emit_tree "project hooks" .claude/hooks '.claude/hooks/**'
if [[ -d .claude/skills ]]; then emit "project skills" "$(count_dirs .claude/skills)" '.claude/skills/*/SKILL.md'; fi
emit_tree "project agents" .claude/agents '.claude/agents/*.md' -name '*.md'

if [[ "$shape" = marketplace ]]; then
  emit "plugins" "$(count_dirs plugins)" 'plugins/*/'
  emit "plugin skills (excl. vendor)" "$(find plugins -path '*/skills/*/SKILL.md' -not -path '*/vendor/*' 2>/dev/null | count_lines)" 'plugins/*/skills/*/SKILL.md'
  emit "plugin skill spokes (excl. vendor)" "$(find plugins -path '*/skills/*' -name '*.md' -not -name SKILL.md -not -path '*/vendor/*' 2>/dev/null | count_lines)" 'plugins/*/skills/**/*.md'
  emit "plugin agents" "$(find plugins -path '*/agents/*.md' 2>/dev/null | count_lines)" 'plugins/*/agents/*.md'
  emit "plugin hook dirs" "$(find plugins -mindepth 2 -maxdepth 2 -type d -name hooks 2>/dev/null | count_lines)" 'plugins/*/hooks/**'
  emit "plugin READMEs" "$(find plugins -mindepth 2 -maxdepth 2 -name README.md 2>/dev/null | count_lines)" 'plugins/*/README.md'
  if [[ -d docs/conventions ]]; then emit "conventions" "$(count_dirs docs/conventions)" 'docs/conventions/*/README.md'; fi
  emit_tree "upstream drift ledgers" docs/upstream 'docs/upstream/*.md' -maxdepth 1 -name '*.md'
  emit_file "native-surfaces store" docs/native-surfaces/records.json
  emit_file "official-docs index" docs/official-docs.md
  emit_tree "repo scripts" scripts 'scripts/*' -maxdepth 1
fi

vendor="$(find . -path '*/skills/*/vendor' -type d -prune 2>/dev/null | count_lines)"
if [[ "$vendor" -gt 0 ]]; then
  echo "excluded: $vendor vendor tree(s) under */skills/*/vendor (upstream reference material)"
fi
exit 0
