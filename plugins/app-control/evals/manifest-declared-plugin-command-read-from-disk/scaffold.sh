#!/usr/bin/env bash
# Seeds a plugin kept in the skills folder whose manifest maps control-shop to a file outside commands/.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin=.claude/skills/shop-tools
mkdir -p "$plugin/.claude-plugin" "$plugin/tooling" evidence
cp "$here/fixtures/plugin.json" "$plugin/.claude-plugin/plugin.json"
cp "$here/fixtures/shop-driver.md" "$plugin/tooling/shop-driver.md"
