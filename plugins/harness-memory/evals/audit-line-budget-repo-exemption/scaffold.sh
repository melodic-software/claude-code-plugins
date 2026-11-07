#!/usr/bin/env bash
# Seeds a repository whose CLAUDE.md runs 260 lines, over the 200-line target,
# while its own rules declare that target waived because the repo runs a large
# rules layer on purpose.
set -euo pipefail

git init -q -b main
git config user.name dev
git config user.email dev@example.invalid

mkdir -p .claude/rules src
services="accounts billing catalog checkout coupons delivery events exports fulfillment gateway
identity imports inventory invoices ledger loyalty mailer media notifications orders payments
pricing profiles promotions ratings recommendations refunds reports returns reviews search
sessions shipping stock subscriptions suppliers support tax tenants uploads vouchers warehouse
webhooks wishlist"
{
  echo "# Storefront platform"
  echo
  echo "Monorepo for the storefront services. Build with \`make build\`, test with \`make test\`."
  echo "Instruction budget policy: \`.claude/rules/instruction-budget.md\`."
  echo
  for s in $services; do
    echo "## $s"
    echo
    echo "- Owner channel: #team-$s."
    echo "- Entry point: \`src/$s/main.go\`."
    echo
  done
  echo "## Shared environment"
  echo
} >CLAUDE.md
n=1
while [ "$(grep -c . CLAUDE.md)" -lt 260 ]; do
  printf -- '- `STORE_SHARED_%02d` is read by every service at start.\n' "$n" >>CLAUDE.md
  n=$((n + 1))
done

for s in $services; do
  mkdir -p "src/$s"
  printf 'package main\n' >"src/$s/main.go"
done

cat >.claude/rules/instruction-budget.md <<'MD'
# Instruction budget

This repository deliberately runs a large `.claude/rules/` layer, one rule per service, and keeps a
long root CLAUDE.md as the service map. We exempt CLAUDE.md from the 200-line target: do not report
its length as a defect.
MD

for s in billing checkout payments; do
  cat >".claude/rules/$s.md" <<MD
---
paths:
  - "src/$s/**"
---

# $s

- Run \`make test-$s\` after any change here.
MD
done

git add -A
git commit -q -m "chore: initial commit"
