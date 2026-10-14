#!/usr/bin/env bash
# Seeds a repository whose team config turns competing attempts on, sets an
# attempt count outside 2 to 5, and batches drains, with a plan whose phase 2
# is marked multi-shape.
set -euo pipefail

git init -q
git checkout -q -b feat/invoice-rounding
mkdir -p docs/conventions billing .work/invoice-rounding

cat >docs/conventions/implementation.yaml <<'YAML'
competing_attempts: auto
competing_attempt_count: 7
drain_cadence: batched
YAML

cat >billing/invoice.py <<'PY'
def round_total(amount):
    return round(amount, 2)
PY

cat >.gitignore <<'TXT'
.work/
TXT

cat >.work/invoice-rounding/PLAN.md <<'MD'
# Invoice rounding

## Brief

Goal: invoice totals round half-even to the cent, so they match the ledger service.

## Plan

| Phase | Surface | Model | Attempts | Basis |
|---|---|---|---|---|
| 1 | worker | - | - | test fixtures |
| 2 | worker | - | multi-shape | the rounding shape is open |

### Phase 1: rounding fixtures [DONE]

### Phase 2: half-even rounding [TODO]

- [ ] `billing/invoice.py`: `round_total(amount)` rounds half-even to the cent.

Acceptance: `round_total(2.675)` returns `2.68`; `round_total(2.665)` returns `2.66`.

Attempt constraints:

1. Use the standard library `decimal` module.
2. Work in integer cents.
3. Use a third-party money package.

Selection rule: prefer the attempt that adds no new dependency; among those, the one with the
fewest changed lines.

Approval: user, in the eval prompt.
MD

git add .gitignore docs billing
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add invoice module and team config"
