#!/usr/bin/env bash
# A Python repository tested with pytest and linted with ruff, whose ruff selection leaves the
# assert-on-tuple diagnostic off, and a findings file whose one row is a testing:audit
# rule-inert-assertion finding on that test.
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

[tool.ruff.lint]
select = ["E", "W", "I"]
EOF
cat >src/shop/pricing.py <<'EOF'
def total(prices, rate):
    return sum(prices) * (1 + rate)
EOF
cat >tests/test_pricing.py <<'EOF'
from shop.pricing import total


def test_total_applies_tax():
    result = total([10], 0.2)
    assert (result == 12, "total should include tax")
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
| 1 | IMPORTANT | high | tests/test_pricing.py:6 | testing:audit | testing/audit/rule-inert-assertion fired=1 excerpt=assert (result == 12, "total should include tax") | Assert the comparison itself, not a tuple that is always true. |

## Unparsed

None.

## Surfaces

Ran: testing:audit.
EOF
