#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p .claude/skills/control-shop/features/billing/export
cp "$here/fixtures/control-shop.md" .claude/skills/control-shop/SKILL.md
cp "$here/fixtures/export-README.md" .claude/skills/control-shop/features/billing/export/README.md
