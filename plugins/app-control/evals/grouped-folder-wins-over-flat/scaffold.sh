#!/usr/bin/env bash
# Seeds a control skill whose checkout feature is a folder, with a stale flat file at the same id.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill=.claude/skills/control-shop
mkdir -p "$skill/features/store/checkout" evidence
cp "$here/fixtures/control-shop.md" "$skill/SKILL.md"
cp "$here/fixtures/checkout-README.md" "$skill/features/store/checkout/README.md"
cp "$here/fixtures/checkout-legacy.md" "$skill/features/store/checkout.md"
