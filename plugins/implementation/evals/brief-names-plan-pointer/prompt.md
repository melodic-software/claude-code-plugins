---
description: "Unprompted, a worker brief names the plan by absolute path under the orchestrator's checkout, so the worker and any later /verification:confirm can read the Brief; the prompt never asks for the path."
tags: [intent-r2, implement-dispatch, brief]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The printed brief names /srv/dev/billing/.work/late-fee/PLAN.md by absolute path."
---

Compose the worker brief for phase 2 of the plan below; I'll dispatch it to the implementer subagent myself. Don't dispatch and don't read any files; print the brief text in full.

- Orchestrator checkout: /srv/dev/billing on `main`. The approved plan is `.work/late-fee/PLAN.md` in that checkout's gitignored `.work/` folder.
- The item's worktree already exists at /srv/dev/wt/late-fee on branch `feat/late-fee`. Commit authority: worker.
- Goal: charge a late fee on invoices paid after their due date.
- Phase 1 [DONE]: `days_overdue(invoice, paid_on)` in `billing/dates.py`.
- Phase 2 (worker): `late_fee(invoice, paid_on)` in `billing/fees.py`, 1.5% of the balance per started 30 days overdue; tests in `tests/test_fees.py`. Acceptance: an invoice paid on time has no fee; 31 days late gives two periods; `pytest` green.
- Design: none.
