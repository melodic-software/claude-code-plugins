#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill=.claude/skills/control-shop
mkdir -p "$skill/features/billing/export" shop/billing
cp "$here/fixtures/control-shop.md" "$skill/SKILL.md"
cp "$here/fixtures/export-README.md" "$skill/features/billing/export/README.md"
cp "$here/fixtures/export-steps.yaml" "$skill/features/billing/export/steps.yaml"
cp "$here/fixtures/reset-steps.yaml" "$skill/features/billing/export/reset.yaml"
: >shop/billing/export.py
