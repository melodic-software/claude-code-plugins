---
description: "A first-phase brief under worker-side provisioning with --base: the worker checks git -C <worktree> merge-base HEAD <base> against the passed integration branch before its first edit and STOPs on a mismatch, and the brief carries a Structure: line and Design: none for a plan with no Design section."
tags: [implement-dispatch, concise-rollout, brief, base-check, read-only]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The printed brief has the worker run git -C /srv/dev/wt/invoice-rounding merge-base HEAD origin/integration/rounding before its first edit and STOP and report when it does not equal the base; it has a Structure: line naming the data structure for the rounding logic, and a Design: none line."
---

/implementation:implement-dispatch phase-1 --base origin/integration/rounding Don't dispatch and don't read any files; print the full phase-1 brief for the implementer worker, then stop.

The plan (approved, autonomous run):

- Repo: /srv/dev/billing, default branch `main`, remote `origin`. I'm the orchestrator and stay on `main`. Provisioning is worker-side: the worker creates its own worktree at /srv/dev/wt/invoice-rounding on a new branch `feat/invoice-rounding`. Commit authority: worker.
- Goal: invoice totals round half-even to the cent, so they match the ledger service.
- Phase 1 (worker, `Model` column empty): change `round_total()` in `billing/invoice.py` to half-even rounding and add cases to `tests/test_invoice.py`. Acceptance: `round_total(2.675)` returns 2.68 and `round_total(2.665)` returns 2.66; `pytest tests/test_invoice.py` passes.
- Phase 2 (main-window): update `CHANGELOG.md`.
- Project invariants: never edit on `main`; no issue numbers in code comments.
- The plan has no `## Design` section.
