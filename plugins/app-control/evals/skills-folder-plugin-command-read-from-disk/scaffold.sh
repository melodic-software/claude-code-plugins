#!/usr/bin/env bash
# Seeds a plugin kept in the skills folder that ships control-shop as a command file with a dynamic-context line.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin=.claude/skills/shop-tools
mkdir -p "$plugin/.claude-plugin" "$plugin/commands" evidence
cp "$here/fixtures/plugin.json" "$plugin/.claude-plugin/plugin.json"
cp "$here/fixtures/control-shop.md" "$plugin/commands/control-shop.md"
