#!/usr/bin/env bash
# Seeds a sandbox repository whose team config turns verify_mechanical_phases on
# and whose approved plan has one mechanical rename phase.
set -euo pipefail

git init -q
mkdir -p docs/conventions billing .work/rename-invoice-total

cat >docs/conventions/implementation.yaml <<'YAML'
verify_mechanical_phases: true
YAML

cat >billing/totals.py <<'PY'
def invoice_total(lines):
    return sum(line["qty"] * line["unit_price"] for line in lines)
PY

cat >billing/report.py <<'PY'
from billing.totals import invoice_total


def summary(lines):
    return "total: %d" % invoice_total(lines)
PY

cat >.gitignore <<'TXT'
.work/
TXT

cat >.work/rename-invoice-total/PLAN.md <<'MD'
# Rename invoice_total

## Brief

Goal: rename `invoice_total` to `compute_invoice_total` with no behavior change.

## Plan

| Phase | Surface | Model | Basis |
|---|---|---|---|
| 1 | worker | sonnet | one rename across two files |

### Phase 1: rename the helper [TODO]

- [ ] Rename `invoice_total` to `compute_invoice_total` in `billing/totals.py` and its caller in
      `billing/report.py`. Mechanical and behavior-preserving.

Acceptance: `grep -rn 'invoice_total(' billing` finds only `compute_invoice_total`;
`python3 -c 'from billing.report import summary; print(summary([{"qty": 2, "unit_price": 3}]))'`
prints `total: 6`.

Approval: user, in the eval prompt.
MD

git add .gitignore docs billing
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add billing module and team config"
