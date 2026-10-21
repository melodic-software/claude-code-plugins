#!/usr/bin/env bash
# A warehouse pick-list app plus a locked PRD in the topic's memory slice with a Problem, a Vision
# line and one assumption. The interview should seed the Brief's Problem from the PRD's Problem and
# carry the assumption into Captured assumptions tagged (from PRD), never as a constraint row.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src/picking .work/pick-list-reprint

cat >src/picking/__init__.py <<'PY'
PY

cat >src/picking/pick_list.py <<'PY'
from dataclasses import dataclass


@dataclass
class PickLine:
    sku: str
    bin: str
    quantity: int


@dataclass
class PickList:
    order_id: str
    lines: list[PickLine]


def render_for_printer(pick_list: PickList) -> str:
    rows = [f"{line.bin}  {line.sku}  x{line.quantity}" for line in pick_list.lines]
    return "\n".join([f"Order {pick_list.order_id}", *rows])
PY

cat >README.md <<'MD'
# Picking

Prints a paper pick list per order at the dispatch desk.
MD

cat >.work/pick-list-reprint/PRD.md <<'MD'
---
status: locked
tier: one-pager
created: 2026-10-01T09:00:00Z
updated: 2026-10-02T09:00:00Z
---

# Pick list on the floor

## Problem

Pickers who lose or smudge their paper pick list walk back to the dispatch desk to have it
reprinted, a dozen round trips a shift across the warehouse.

## Goals

- A picker can bring up the current pick list for an order without leaving the aisle.
- Vision: every floor task a picker gets arrives on the device in their hand, not on paper.

## Non-goals

- Retiring the paper pick list for pickers who still want it.

## Users

- Primary: warehouse pickers on the day shift.
- As a picker, I want to open my order's pick list where I stand, so that I do not walk back to
  the desk for a reprint.

## Success metrics

- Reprint requests at the dispatch desk fall by half within four weeks of launch.

## Dependencies / risks

- Warehouse Wi-Fi drops in the far aisles; mitigation: the list stays readable once loaded.

## Assumptions

- Every picker's handheld scanner has a browser that can open an internal web page; shown false
  if a scanner model on the floor has no browser.

## Open questions

None.
MD

git add src README.md
git commit -q -m "feat: printable pick list"
