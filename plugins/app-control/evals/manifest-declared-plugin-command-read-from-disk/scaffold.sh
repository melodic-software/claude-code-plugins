#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin=.claude/skills/shop-tools
mkdir -p "$plugin/.claude-plugin" "$plugin/tooling" evidence
cp "$here/fixtures/plugin.json" "$plugin/.claude-plugin/plugin.json"
cp "$here/fixtures/shop-driver.md" "$plugin/tooling/shop-driver.md"
