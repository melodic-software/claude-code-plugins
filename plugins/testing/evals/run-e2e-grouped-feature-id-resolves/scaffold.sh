#!/usr/bin/env bash
# Seeds the shop app's control skill with a grouped feature, billing/export (plus a stray legacy
# billing/export.md), and a legacy flat feature, cart (plus a cart/ folder with no README.md).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill=.claude/skills/control-shop
mkdir -p "$skill/features/billing/export" "$skill/features/cart"
cp "$here/fixtures/control-shop.md" "$skill/SKILL.md"
cp "$here/fixtures/export-README.md" "$skill/features/billing/export/README.md"
cp "$here/fixtures/export-legacy.md" "$skill/features/billing/export.md"
cp "$here/fixtures/cart.md" "$skill/features/cart.md"
cp "$here/fixtures/cart-steps.md" "$skill/features/cart/steps.md"
