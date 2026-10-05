---
description: "Control. A docs-only phase changes no behavior, so its brief must not demand proof that a test fails without the change; guards against a red-run requirement applied to every phase."
tags: [pocock-r1, implement-dispatch, brief, control]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The printed phase-3 brief for the docs-only edit asks for no failing-test or red-run evidence; it may ask for the docs lint or build to pass."
---

We're executing an approved plan with worker subagents, and I need the brief for phase 3 that goes to the implementer worker. Don't dispatch anything and don't read any files; print the complete brief text I'd hand the worker.

The plan (approved, autonomous run, no human in the loop):

- Repo: /srv/dev/orders-api, default branch `main`. The item's worktree already exists at /srv/dev/wt/orders-rate-limit on branch `feat/orders-rate-limit`. Commit authority: worker.
- Goal: per-client rate limiting on `POST /orders`, so one noisy client can no longer starve the others.
- Phase 1 [DONE]: `RateLimiter` class in `src/limits/rate_limiter.py` with unit tests.
- Phase 2 [DONE]: `POST /orders` returns 429 with `Retry-After` over 100 requests a minute.
- Phase 3 (worker, no model routing): document the limit in `docs/api.md`: the 100-per-minute ceiling, the 429 status, and the `Retry-After` header. Acceptance: the section exists and `make docs-lint` passes. No code or test changes.
- Project invariants: no issue numbers in code comments.
- Design: none.
