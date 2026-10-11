---
description: "Item-list mode with no PLAN.md: the first wave holds the item the tracker reports blocked and dispatches the ready ones together, and the brief checks the worktree base against the integration branch passed as the base, not the default branch."
tags: [implement-dispatch, item-list, brief]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply needs no plan. Its first wave has #41 and #43 and holds #42 because the tracker reports an open blocker. The #41 brief has the worker confirm before its first edit that its branch's merge-base equals origin/integration/rounding, and STOP on a mismatch."
---

Run these work items with /implementation:implement-dispatch, passing `--items` and `--base origin/integration/rounding`. There is no PLAN.md; the list below is the spec. Don't dispatch anything and don't run commands. Print which items go in the first wave and which are held and why, then the full brief for acme/billing#41.

Repo: /srv/dev/billing, default branch `main`. I'm the orchestrator and stay on `main`. Each worker provisions its own worktree; commit authority: worker. Autonomous run.

Item list:

- id: github:acme/billing#41. title: Half-even rounding helper. targets: billing/rounding.py. acceptance: `round_half_even(2.675)` returns 2.68; `pytest tests/test_rounding.py` passes. branch: feat/41-rounding.
- id: github:acme/billing#42. title: Invoice totals use the helper. targets: billing/invoice.py. acceptance: invoice totals round half-even; `pytest tests/test_invoice.py` passes. branch: feat/42-invoice.
- id: github:acme/billing#43. title: Tax lines use the helper's constants. targets: billing/tax.py. acceptance: `pytest tests/test_tax.py` passes. branch: feat/43-tax.

I wrote this list. The tracker seam's `list-frontier` probe exited 0, and its `get-item` already returned: github:acme/billing#41 open, blocked_by_count 0; github:acme/billing#42 open, blocked_by_count 1 (blocked by #41); github:acme/billing#43 open, blocked_by_count 0.
