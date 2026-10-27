#!/usr/bin/env bash
# Seeds a plugin kept in the skills folder that ships control-shop as a skill, the repository's only control skill.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin=.claude/skills/shop-tools
mkdir -p "$plugin/.claude-plugin" "$plugin/skills/control-shop" evidence
cp "$here/fixtures/plugin.json" "$plugin/.claude-plugin/plugin.json"
cp "$here/fixtures/SKILL.md" "$plugin/skills/control-shop/SKILL.md"
