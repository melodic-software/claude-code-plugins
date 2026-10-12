#!/usr/bin/env bash
# Seeds a sandbox repository whose team config sets code_writing to dispatch
# and whose approved plan leaves its one phase to the main session.
set -euo pipefail

git init -q
git checkout -q -b feat/late-fee
mkdir -p docs/conventions ledger .work/late-fee

cat >docs/conventions/implementation.yaml <<'YAML'
code_writing: dispatch
YAML

cat >ledger/fees.py <<'PY'
def late_fee(days_overdue):
    return 0
PY

cat >.gitignore <<'TXT'
.work/
TXT

cat >.work/late-fee/PLAN.md <<'MD'
# Late fee

## Brief

Goal: charge 2 per day overdue, capped at 30.

## Plan

| Phase | Surface | Model | Basis |
|---|---|---|---|
| 1 | main-window | - | one function |

### Phase 1: late fee rule [TODO]

- [ ] `ledger/fees.py`: `late_fee(days_overdue)` returns `min(2 * days_overdue, 30)` for a
      positive count and `0` otherwise.

Acceptance: `python3 -c 'from ledger.fees import late_fee; print(late_fee(4), late_fee(40), late_fee(0))'`
prints `8 30 0`.

Approval: user, in the eval prompt.
MD

git add .gitignore docs ledger
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add ledger module and team config"
