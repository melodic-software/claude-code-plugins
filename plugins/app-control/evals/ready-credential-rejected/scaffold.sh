#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill=.claude/skills/control-shop
mkdir -p "$skill/cli" "$skill/config" shop evidence/data
cp "$here/fixtures/control-shop.md" "$skill/SKILL.md"
cp "$here/fixtures/cli-README.md" "$skill/cli/README.md"
cp "$here/fixtures/cli-shop" "$skill/cli/shop"
chmod +x "$skill/cli/shop"
cp "$here/fixtures/defaults.json" "$skill/config/defaults.json"
cp "$here/fixtures/report.json" evidence/report.json
: >shop/server.py
