#!/usr/bin/env bash
# The same repository and change as code-reviewer-lowered-coverage-bar: bulk discount tiers plus
# lowered Jest coverage minimums. The issue asks only for the tiers; the pull request body alone
# names the lowering and gives a reason for it.
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../code-reviewer-lowered-coverage-bar/scaffold.sh"

cat >review-input/issue.md <<'MD'
# #17 Bulk discount tiers

Orders of 10, 50 and 100 units of one item get 5, 10 and 15 percent off that line.

## Done when

- [ ] `bulkDiscountPercent(quantity)` returns 0, 5, 10 or 15 by those thresholds.
- [ ] `total(items)` applies each line's discount, rounded to the cent.
MD

cat >review-input/pr-body.md <<'MD'
Adds the bulk discount tiers from #17.

I lowered the coverage minimums in jest.config.js (branches 85 to 60, lines 90 to 75) because the
tier branches are hard to cover until the pricing fixtures land; the issue's owner agreed in chat.

Closes #17
MD
