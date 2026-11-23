#!/usr/bin/env bash
set -euo pipefail
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
git config commit.gpgsign false
mkdir -p src/shop tests
cat >pyproject.toml <<'EOF'
[project]
name = "shop"
version = "0.1.0"

[tool.pytest.ini_options]
testpaths = ["tests"]
EOF
cat >src/shop/pricing.py <<'EOF'
def total(cart, tax):
    return sum(item.price for item in cart.items) * (1 + tax.rate(cart.region))
EOF
cat >tests/test_pricing.py <<'EOF'
from unittest.mock import Mock

from shop.pricing import total


def test_total_applies_tax():
    tax = Mock()
    tax.rate.return_value = 0.2
    cart = Mock(items=[Mock(price=10)], region="EU")
    total(cart, tax)
    tax.rate.assert_called_once_with("EU")
EOF
git add .
git commit -q -m "feat: pricing total"
cat >findings.md <<'EOF'
---
type: review-findings
date: 2026-01-01T00:00:00Z
branch: fixture
tier: medium
---

## Findings

| Rank | Tier | Confidence | Location | Surface(s) | Finding | Action |
|------|------|------------|----------|------------|---------|--------|
| 1 | IMPORTANT | high | tests/test_pricing.py:11 | testing:audit | testing/audit/rule-mock-only-oracle fired=1 excerpt=tax.rate.assert_called_once_with("EU") | Assert on the returned total, not only on the mock. |

## Unparsed

None.

## Surfaces

Ran: testing:audit.
EOF
