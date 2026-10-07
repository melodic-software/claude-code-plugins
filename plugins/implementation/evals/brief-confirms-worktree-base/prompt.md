---
description: "The first-phase brief under worker-side provisioning must tell the worker to confirm its new worktree branch starts from the intended base before its first edit, not only to create it or to merge the default branch before returning."
tags: [pocock-r1, implement-dispatch, brief]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The printed phase-1 brief has the worker, after provisioning its worktree and before its first edit, check that the branch's base is the intended one (for example that HEAD or the merge-base equals freshly fetched origin/main) and STOP and report when it is not. Creating the worktree from a named base, or bringing the branch current before returning, is not the check."
---

I'm fanning an approved plan out to worker subagents. Write the brief for phase 1, the first dispatched phase of this item, for the implementer worker. Don't dispatch and don't read any files; print the full brief text.

The plan (approved, autonomous run):

- Repo: /srv/dev/billing, default branch `main`. I'm the orchestrator and I stay on `main`; the worker provisions its own worktree on branch `feat/invoice-rounding`. Commit authority: worker.
- Goal: invoice totals round half-even to the cent, so they match the ledger service.
- Phase 1 (worker): change `round_total()` in `billing/invoice.py` to half-even rounding and add cases to `tests/test_invoice.py`. Acceptance: 2.675 rounds to 2.68 and 2.665 to 2.66; existing tests still pass with `pytest`.
- Phase 2: update `CHANGELOG.md`.
- Project invariants: never edit on `main`; no issue numbers in code comments.
- Design: none.
