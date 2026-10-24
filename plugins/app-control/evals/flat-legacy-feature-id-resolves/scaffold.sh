#!/usr/bin/env bash
# Seeds the shop app's control skill with one legacy flat feature file, cart.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p .claude/skills/control-shop/features
cp "$here/fixtures/control-shop.md" .claude/skills/control-shop/SKILL.md
cp "$here/fixtures/cart.md" .claude/skills/control-shop/features/cart.md
