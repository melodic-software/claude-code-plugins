#!/usr/bin/env bash
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

printf '.work/\n' >.gitignore
printf '# shop\n\nA small storefront.\n' >README.md
mkdir -p docs/conventions
cat >docs/conventions/work-items.yaml <<'YAML'
tracker:
  schema_version: "1.0"
  provider: github
  config:
    lease_ttl_hours: 24
YAML
printf 'dossier_branch_prefix: dossier/\n' >docs/conventions/source-control.yaml
git add .
git commit -q -m "chore: scaffold storefront"
mkdir -p src
printf 'export const steps = ["cart", "pay"];\n' >src/checkout.js
git add src/checkout.js
git commit -q -m "feat: one-page checkout (#401)"
printf 'export const guestCheckout = true;\n' >src/guest.js
git add src/guest.js
git commit -q -m "feat: keep guest checkout (#402)"

git init -q --bare -b main .work/origin.git
git remote add origin .work/origin.git
git push -q origin main

git switch -q -c dossier/400-checkout-redesign
mkdir -p notes prototype
printf '# Research\n\nCart abandonment peaks at the shipping step.\n' >notes/research.md
git add notes/research.md
git commit -q -m "docs: checkout research notes"
printf '# Decisions\n\nOne-page checkout; guest checkout stays.\n' >notes/decisions.md
git add notes/decisions.md
git commit -q -m "docs: checkout decisions"
printf '<!doctype html>\n<title>Checkout sketch</title>\n' >prototype/sketch.html
git add prototype/sketch.html
git commit -q -m "docs: checkout prototype sketch"
git push -q origin dossier/400-checkout-redesign

git switch -q main
git switch -q -c dossier/400-checkout-v2
mkdir -p notes
printf '# Checkout v2\n\nAlternative flow notes.\n' >notes/v2.md
git add notes/v2.md
git commit -q -m "docs: checkout v2 notes"
git push -q origin dossier/400-checkout-v2

git switch -q main
git branch -q -D dossier/400-checkout-redesign dossier/400-checkout-v2
git fetch -q origin
git remote set-head origin main
