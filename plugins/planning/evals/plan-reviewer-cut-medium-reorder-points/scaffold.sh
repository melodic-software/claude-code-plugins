#!/usr/bin/env bash
# An inventory package with an available-stock helper and a weekly report, and a draft plan for reorder points.
set -euo pipefail

mkdir -p .work/reorder-points/design inventory
cat >README.md <<'EOF'
# inventory

Stock levels, the weekly report and the buyers' CLI (`python -m inventory.cli`).
EOF
: >inventory/__init__.py
cat >inventory/stock.py <<'EOF'
"""Stock levels. STOCK and RESERVED are loaded from the warehouse export at start-up."""
STOCK = {}
RESERVED = {}


def on_hand(sku):
    return STOCK.get(sku, 0)


def reserved(sku):
    return RESERVED.get(sku, 0)


def available(sku):
    """Stock free to sell: on hand minus reserved, never below zero."""
    return max(on_hand(sku) - reserved(sku), 0)
EOF
cat >inventory/report.py <<'EOF'
from inventory import stock


def weekly_report():
    rows = [(sku, stock.on_hand(sku), stock.reserved(sku)) for sku in sorted(stock.STOCK)]
    return "\n".join("%-10s %6d %6d" % row for row in rows)
EOF
cat >inventory/cli.py <<'EOF'
import argparse

from inventory import report


def main(argv=None):
    parser = argparse.ArgumentParser(prog="inventory")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("weekly")
    args = parser.parse_args(argv)
    if args.command == "weekly":
        print(report.weekly_report())


if __name__ == "__main__":
    main()
EOF
cat >.work/reorder-points/PLAN.md <<'EOF'
# Reorder points

## Brief

### Problem
Buyers notice a product is short only when an order cannot be filled.

### Goal
A `reorder` command lists the products whose free stock has fallen below their reorder point.

### Acceptance criteria
- AC1: `inventory reorder` lists each SKU whose free stock (on hand minus reserved) is below its reorder point.
- AC2: Reorder points are read from `inventory/data/reorder_points.json`; a SKU with no entry is never listed.
- AC3: The list is sorted by SKU.

### Out-of-scope
- Changing the weekly stock report.
- Placing orders with suppliers.

## Design

Early exit (tier C): A new command over existing stock functions; no new types.

## Plan

### Behavior
- B1: Products below their reorder point are listed by SKU (AC1, AC3). Delivered by Phase 1 and Phase 2.
- B2: Products with no reorder point are never listed (AC2). Delivered by Phase 1.

### Load-bearing assumptions

| Assumption | Source | Falsifying check | Response if false |
|---|---|---|---|
| Reserved stock never exceeds stock on hand | plan | Phase 1 Sanity Check | Moderate: flag and continue |

### Phase 1: Reorder check [STATUS]
**Satisfies:** AC1, AC2
**Delivers:** B1, B2

- Create `inventory/data/reorder_points.json` with the buyers' points.
- Add `inventory/reorder.py` with `below_reorder_point()`: for each SKU in the points file, compute `stock.on_hand(sku) - stock.reserved(sku)` and keep it when below the point.
- In `tests/test_reorder.py`, cover a SKU below, at and above its point, and one with no point.

**Sanity Check:** `python -m unittest tests.test_reorder` exits 0.

### Phase 2: Command and report [STATUS]
**Satisfies:** AC1, AC3
**Delivers:** B1

- In `inventory/cli.py`, add `reorder`, printing `below_reorder_point()` sorted by SKU.
- In `inventory/report.py`, add a `Below reorder point` column to `weekly_report()`.

**Sanity Check:** `python -m unittest discover -s tests` exits 0.

### Files affected
| File | Action |
|---|---|
| `inventory/data/reorder_points.json` | create |
| `inventory/reorder.py` | create |
| `inventory/cli.py` | modify |
| `inventory/report.py` | modify |
| `tests/test_reorder.py` | create |
EOF
cat >.work/reorder-points/design/design-resolution.md <<'EOF'
outcome: early-exit
tier: C
reason: A new command over existing stock functions; no new types.
EOF
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/plan-reviewer-cut/init-repo.sh" feat/reorder-points
