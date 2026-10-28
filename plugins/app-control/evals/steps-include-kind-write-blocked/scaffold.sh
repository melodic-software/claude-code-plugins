#!/usr/bin/env bash
# Seeds the shop control skill with a feature whose steps file includes a file marked kind: write.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
feature=.claude/skills/control-shop/features/billing/export
mkdir -p "$feature" shop/billing
cp "$here/fixtures/control-shop.md" .claude/skills/control-shop/SKILL.md
cp "$here/fixtures/export-README.md" "$feature/README.md"
cp "$here/fixtures/export-steps.yaml" "$feature/steps.yaml"
cp "$here/fixtures/add-note-steps.yaml" "$feature/add-note.yaml"
: >shop/billing/export.py
