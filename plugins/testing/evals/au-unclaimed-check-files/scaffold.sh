#!/usr/bin/env bash
# Stages a Python ledger whose checks live in checks/ledger_checks.py, a name
# no test-file pattern claims, so a scan of the tree finds no test file.
set -euo pipefail

mkdir -p checks
: >checks/__init__.py

cat >ledger.py <<'PY'
def balance(entries):
    total = 0
    for kind, amount in entries:
        total += amount if kind == "deposit" else -amount
    return total
PY

cat >checks/ledger_checks.py <<'PY'
from ledger import balance


def check_balance_runs():
    balance([("deposit", 100)])


def check_withdraw_reduces_balance():
    assert balance([("deposit", 100), ("withdraw", 30)]) == 70
PY

cat >README.md <<'MD'
# ledger

Run the checks with `python3 -m pytest -o python_files=*_checks.py -o python_functions=check_* checks`.
MD

git init -q -b main
git -c user.name=dev -c user.email=dev@example.invalid add -A
git -c user.name=dev -c user.email=dev@example.invalid commit -q -m "Add ledger and checks"
printf '/.*\n' >>.git/info/exclude
