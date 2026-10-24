#!/usr/bin/env bash
# Seeds the shop app's control skill and the run directory holding this run's launch record.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p .claude/skills/control-shop evidence
cp "$here/fixtures/control-shop.md" .claude/skills/control-shop/SKILL.md
cp "$here/fixtures/report.json" evidence/report.json
