#!/usr/bin/env bash
# Seeds a repository whose team config sets code_writing to a value outside its
# allowed set and integration_posture to a valid value, with no approved plan.
set -euo pipefail

git init -q
git checkout -q -b fix/late-fee
mkdir -p docs/conventions ledger

cat >docs/conventions/implementation.yaml <<'YAML'
code_writing: parallel
integration_posture: minimal
YAML

cat >ledger/fees.py <<'PY'
def late_fee(days_overdue):
    if days_overdue <= 0:
        return 0
    return 3 * days_overdue
PY

git add docs ledger
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add ledger module and team config"
