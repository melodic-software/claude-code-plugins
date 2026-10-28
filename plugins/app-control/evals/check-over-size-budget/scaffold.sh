#!/usr/bin/env bash
# Seeds a control skill whose cart feature file is about twice its size budget.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill=.claude/skills/control-shop
mkdir -p "$skill/features/cart" "$skill/features/billing/export" shop/billing
cp "$here/fixtures/control-shop.md" "$skill/SKILL.md"
cp "$here/fixtures/cart-README.md" "$skill/features/cart/README.md"
for i in $(seq 1 100); do
  printf -- '- Run %03d: the badge count lagged the cart page until the next poll finished.\n' "$i"
done >>"$skill/features/cart/README.md"
cp "$here/fixtures/export-README.md" "$skill/features/billing/export/README.md"
: >shop/cart.py
: >shop/billing/export.py
mkdir -p .claude/skills/run-shop
cp "$here/fixtures/run-shop.md" .claude/skills/run-shop/SKILL.md
