#!/usr/bin/env bash
# Seeds the shop control skill with a feature whose steps file includes one shared file twice.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill=.claude/skills/control-shop
mkdir -p "$skill/features/billing/export" "$skill/shared/pick-month" shop/billing
cp "$here/fixtures/control-shop.md" "$skill/SKILL.md"
cp "$here/fixtures/export-README.md" "$skill/features/billing/export/README.md"
cp "$here/fixtures/export-steps.yaml" "$skill/features/billing/export/steps.yaml"
cp "$here/fixtures/pick-month-README.md" "$skill/shared/pick-month/README.md"
cp "$here/fixtures/pick-month-steps.yaml" "$skill/shared/pick-month/steps.yaml"
: >shop/billing/export.py
