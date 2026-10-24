#!/usr/bin/env bash
# Seeds a project control-shop skill whose checkout feature carries the code HERON-12.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill=.claude/skills/control-shop
mkdir -p "$skill/features/checkout" evidence
cp "$here/fixtures/control-shop.md" "$skill/SKILL.md"
cp "$here/fixtures/checkout-README.md" "$skill/features/checkout/README.md"
