#!/usr/bin/env bash
# Seeds the shop control skill with a feature whose steps file includes one month-picker file twice.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
feature=.claude/skills/control-shop/features/billing/export
mkdir -p "$feature" shop/billing
cp "$here/fixtures/control-shop.md" .claude/skills/control-shop/SKILL.md
cp "$here/fixtures/export-README.md" "$feature/README.md"
cp "$here/fixtures/export-steps.yaml" "$feature/steps.yaml"
cp "$here/fixtures/pick-month-steps.yaml" "$feature/pick-month.yaml"
: >shop/billing/export.py
