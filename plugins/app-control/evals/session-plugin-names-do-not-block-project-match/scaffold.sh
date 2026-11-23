#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for p in shop other; do
  plugin=".claude/skills/$p-tools"
  mkdir -p "$plugin/.claude-plugin" "$plugin/skills/control-$p"
  cp "$here/fixtures/$p-plugin.json" "$plugin/.claude-plugin/plugin.json"
  cp "$here/fixtures/control-$p.md" "$plugin/skills/control-$p/SKILL.md"
done
mkdir -p evidence
