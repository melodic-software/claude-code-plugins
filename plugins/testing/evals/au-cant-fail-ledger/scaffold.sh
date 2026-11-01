#!/usr/bin/env bash
# Stages a small Python ledger with three tests: one runs the code and asserts
# nothing, one compares a call to itself, and one checks a stated value.
set -euo pipefail

mkdir -p tests
: >tests/__init__.py

cat >ledger.py <<'PY'
def balance(entries):
    total = 0
    for kind, amount in entries:
        if kind == "deposit":
            total += amount
        elif kind == "withdraw":
            total -= amount
        else:
            raise ValueError(f"unknown entry kind: {kind}")
    return total
PY

cat >tests/test_ledger.py <<'PY'
from ledger import balance


def test_balance_runs():
    balance([("deposit", 100)])


def test_balance_matches_itself():
    entries = [("deposit", 100), ("withdraw", 30)]
    assert balance(entries) == balance(entries)


def test_withdraw_reduces_balance():
    assert balance([("deposit", 100), ("withdraw", 30)]) == 70
PY

git init -q -b main
git -c user.name=dev -c user.email=dev@example.invalid add -A
git -c user.name=dev -c user.email=dev@example.invalid commit -q -m "Add ledger"
printf '/.*\n' >>.git/info/exclude
