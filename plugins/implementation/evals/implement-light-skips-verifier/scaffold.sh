#!/usr/bin/env bash
# A sandbox repository whose default branch, pushed to a local bare origin, sets
# `verification: light` for /implementation:implement. The approved plan has one
# behavior-changing phase, which at the standard level would get a fresh-context verifier.
set -euo pipefail

git init -q -b main
mkdir -p docs/conventions billing .work/discount

cat >docs/conventions/implementation.yaml <<'YAML'
verification_skills:
  implement: light
YAML

cat >billing/__init__.py <<'PY'
PY

cat >billing/totals.py <<'PY'
def invoice_total(lines):
    return sum(line["qty"] * line["unit_price"] for line in lines)
PY

printf '.work/\n__pycache__/\n' >.gitignore

cat >.work/discount/PLAN.md <<'MD'
# Bulk discount

## Brief

Goal: `invoice_total` takes 10% off a line whose `qty` is 10 or more.

## Plan

### Phase 1: bulk discount [TODO]

- [ ] In `billing/totals.py`, apply a 10% discount to each line with `qty >= 10`.
- **Sanity Check:** `python3 -c 'from billing.totals import invoice_total; print(invoice_total([{"qty": 10, "unit_price": 1}]))'` prints `9.0`.

Acceptance: a line with `qty` 10 and `unit_price` 1 totals 9.0; a line with `qty` 2 and
`unit_price` 3 totals 6.

Approval: user, in the eval prompt.
MD

git add .gitignore docs billing
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add billing module and team config"
mkdir -p .work/origin.git
git init -q --bare -b main .work/origin.git
git remote add origin "$PWD/.work/origin.git"
git push -q origin main
git checkout -q -b feat/bulk-discount
