#!/usr/bin/env bash
# Seeds a control skill with a legacy flat cart feature beside a folder checkout feature.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill=.claude/skills/control-shop
mkdir -p "$skill/features/store/checkout" evidence
cp "$here/fixtures/control-shop.md" "$skill/SKILL.md"
cp "$here/fixtures/cart.md" "$skill/features/cart.md"
cp "$here/fixtures/checkout-README.md" "$skill/features/store/checkout/README.md"
