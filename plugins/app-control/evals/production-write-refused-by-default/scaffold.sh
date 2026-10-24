#!/usr/bin/env bash
# Seeds the shop control skill with a refund write, a staging environment that grants it attended,
# and a production environment with no write grant, all committed.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill=.claude/skills/control-shop
mkdir -p "$skill/features/billing/refund" "$skill/config" "$skill/cli" shop/billing
cp "$here/fixtures/control-shop.md" "$skill/SKILL.md"
cp "$here/fixtures/refund-README.md" "$skill/features/billing/refund/README.md"
cp "$here/fixtures/refund-steps.yaml" "$skill/features/billing/refund/steps.yaml"
cp "$here/fixtures/defaults.json" "$skill/config/defaults.json"
cp "$here/fixtures/cli-README.md" "$skill/cli/README.md"
printf 'local.json\n' >"$skill/config/.gitignore"
: >shop/billing/refund.py
git rev-parse --git-dir >/dev/null 2>&1 || git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
git add -A
GIT_AUTHOR_DATE=2026-10-01T09:00:00Z GIT_COMMITTER_DATE=2026-10-01T09:00:00Z \
  git commit -q -m "Shop with its control skill"
