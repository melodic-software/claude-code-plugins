#!/usr/bin/env bash
# Seeds the shop control skill whose sign-in steps come from an integrated app in another
# repository, with no setting saying where that repository's checkout is.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill=.claude/skills/control-shop
mkdir -p "$skill/features/orders/history" "$skill/config" shop
cp "$here/fixtures/control-shop.md" "$skill/SKILL.md"
cp "$here/fixtures/history-README.md" "$skill/features/orders/history/README.md"
cp "$here/fixtures/history-steps.yaml" "$skill/features/orders/history/steps.yaml"
cp "$here/fixtures/defaults.json" "$skill/config/defaults.json"
printf 'local.json\n' >"$skill/config/.gitignore"
: >shop/serve.py
