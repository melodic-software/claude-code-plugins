---
description: "A two-row wave: each row's brief carries the divergence-escalation clause verbatim, and each FORBIDDEN list names the paths the sibling row owns rather than 'everything else'."
tags: [implement-dispatch, concise-rollout, brief, scope-fence, read-only]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Two briefs, one per row. Both quote 'if an assumption in this brief proves wrong or the task requires touching anything FORBIDDEN, STOP and report. Do not improvise' verbatim. The rounding row's FORBIDDEN list names billing/tax.py (and tests/test_tax.py); the tax row's FORBIDDEN list names billing/rounding.py (and tests/test_rounding.py)."
---

/implementation:implement-dispatch phase-1 Don't dispatch and don't read any files; print the full brief for every worker row of phase 1's first wave, then stop.

The plan (approved, interactive run):

- Repo: /srv/dev/billing, default branch `main`. Commit authority: worker. Each row works in a worktree I already created from current `origin/main`: row A in /srv/dev/wt/rounding (branch `feat/rounding`), row B in /srv/dev/wt/tax (branch `feat/tax`).
- Goal: invoice and tax amounts round half-even to the cent, so they match the ledger service.
- Phase 1 has two independent worker rows, `Model` column empty:
  - Row A: add `round_half_even(amount)` to `billing/rounding.py` and its cases to `tests/test_rounding.py`. Acceptance: `round_half_even(2.675)` returns 2.68 and `round_half_even(2.665)` returns 2.66; `pytest tests/test_rounding.py` passes.
  - Row B: rename the constant `TAX_RATE` to `VAT_RATE` in `billing/tax.py` and update `tests/test_tax.py` to match. Acceptance: no `TAX_RATE` remains in either file; `pytest tests/test_tax.py` passes.
- Project invariants: never edit on `main`; no issue numbers in code comments.
- The plan has no `## Design` section.
