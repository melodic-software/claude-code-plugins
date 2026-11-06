#!/usr/bin/env bash
# One file with a planted boundary defect, in a repository whose default branch sets
# verification: light for the bugs plugin.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src docs/conventions
printf '.work/\n' >.gitignore
printf 'verification: light\n' >docs/conventions/bugs.yaml
cat >src/discount.js <<'JS'
// Discount for an order, by its total in cents.
// Orders of 10000 cents ($100.00) or more get 10% off; 5000 cents or more get 5% off.
export function discountRate(totalCents) {
  if (totalCents > 10000) return 0.1;
  if (totalCents >= 5000) return 0.05;
  return 0;
}
JS
git add -A
git commit -q -m "feat: order discounts"

# The level is read from the default branch on origin, so push main to a local bare origin.
mkdir -p .work/origin.git
git init -q --bare -b main .work/origin.git
git remote add origin "$PWD/.work/origin.git"
git push -q origin main
