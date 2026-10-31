#!/usr/bin/env bash
# Stages a pricing module with a module-level rate table, a campaign test that
# changes the table and never restores it, and the test that then fails.
set -euo pipefail

mkdir -p tests
: >tests/__init__.py

cat >pricing.py <<'PY'
RATES = {"standard": 0.0, "member": 0.05}


def apply_discount(price, tier):
    return round(price * (1 - RATES[tier]), 2)
PY

cat >tests/test_campaigns.py <<'PY'
import pricing


def test_spring_campaign_rate():
    pricing.RATES["standard"] = 0.1
    assert pricing.apply_discount(100, "standard") == 90.0
PY

cat >tests/test_pricing.py <<'PY'
from pricing import apply_discount


def test_apply_discount_standard():
    assert apply_discount(100, "standard") == 100


def test_apply_discount_member():
    assert apply_discount(100, "member") == 95.0
PY

git init -q -b main
git -c user.name=dev -c user.email=dev@example.invalid add -A
git -c user.name=dev -c user.email=dev@example.invalid commit -q -m "Add pricing and spring campaign"
printf '/.*\n' >>.git/info/exclude
