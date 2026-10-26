#!/usr/bin/env bash
# Seeds the shop control skill with a feature whose steps file has one optional step.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill=.claude/skills/control-shop
mkdir -p "$skill/features/billing/export" shop/billing
cp "$here/fixtures/control-shop.md" "$skill/SKILL.md"
cp "$here/fixtures/export-README.md" "$skill/features/billing/export/README.md"
cp "$here/fixtures/export-steps.yaml" "$skill/features/billing/export/steps.yaml"
: >shop/billing/export.py
