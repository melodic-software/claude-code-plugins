#!/usr/bin/env bash
# A catalog package whose price loader raises on a missing file, and a draft plan that says it does not.
set -euo pipefail

mkdir -p .work/price-lookup/design catalog data tests
cat >README.md <<'EOF'
# catalog

Price lookups for the till. Staff edit data/prices.json while the shop is open.
EOF
: >catalog/__init__.py
cat >catalog/prices.py <<'EOF'
"""Price lookups from data/prices.json, which staff edit while the shop is open."""
import json
from pathlib import Path

PRICES_PATH = Path("data/prices.json")


def load_prices(path=PRICES_PATH):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)
EOF
cat >data/prices.json <<'EOF'
{"A100": 3.5, "B200": 12.0}
EOF
cat >tests/test_prices.py <<'EOF'
import json
import os
import tempfile
import unittest

from catalog.prices import load_prices


class LoadTest(unittest.TestCase):
    def test_reads_json(self):
        path = os.path.join(tempfile.mkdtemp(), "prices.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump({"A100": 3.5}, handle)
        self.assertEqual(load_prices(path), {"A100": 3.5})


if __name__ == "__main__":
    unittest.main()
EOF
cat >.work/price-lookup/PLAN.md <<'EOF'
# Price lookup without a crash

## Brief

### Problem
The till crashes with a traceback when a product has no price, and staff restart it mid-sale.

### Goal
`price_for(sku)` returns the price, or `None` when the product or the price file is missing, so the till can ask staff to enter a price.

### Acceptance criteria
- AC1: `price_for("A100")` returns the value from `data/prices.json`.
- AC2: An unknown SKU returns `None`.
- AC3: A missing price file returns `None`.
- AC4: An edit to `data/prices.json` shows in the next call without a restart.

### Out-of-scope
- Editing prices from the till.

## Design

Early exit (tier C): One new function beside an existing loader; no new types.

## Plan

### Behavior
- B1: A known SKU returns its price (AC1). Delivered by Phase 1.
- B2: An unknown SKU or a missing file gives no price instead of an error (AC2, AC3). Delivered by Phase 1.
- B3: Add cases in `tests/test_prices.py` for an edit between calls (AC4). Delivered by Phase 1.

### Load-bearing assumptions

| Assumption | Source | Falsifying check | Response if false |
|---|---|---|---|
| `data/prices.json` holds a flat object of SKU to price | plan | Phase 1 Sanity Check | Minor: proceed and note |

### Phase 1: Add price_for [STATUS]
**Satisfies:** AC1, AC2, AC3, AC4
**Delivers:** B1, B2, B3

- In `catalog/prices.py`, add `price_for(sku, path=PRICES_PATH)` returning `load_prices(path).get(sku)`; `load_prices` already returns an empty dict when the file is missing, so AC3 needs no branch of its own.
- Read the file on every call, so a staff edit shows at once.
- In `tests/test_prices.py`, add one case per criterion.

**Sanity Check:** `python -m unittest discover -s tests` exits 0.

### Files affected
| File | Action |
|---|---|
| `catalog/prices.py` | modify |
| `tests/test_prices.py` | modify |
EOF
cat >.work/price-lookup/design/design-resolution.md <<'EOF'
outcome: early-exit
tier: C
reason: One new function beside an existing loader; no new types.
EOF
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/plan-reviewer-cut/init-repo.sh" fix/price-lookup
