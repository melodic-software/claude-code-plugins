---
description: "The brief for a behavior-changing phase must make the worker return proof that its new test fails without the change (red-run evidence), stated as a return requirement rather than a red-green cadence."
tags: [pocock-r1, implement-dispatch, brief]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The printed phase-2 brief requires the worker's return to carry evidence that the 429 test fails without the change: the failing test output against the code before the edit, or the change reverted. A brief that only asks for a green suite, or tells the worker to follow red-green-refactor without asking it to report the failing run, does not pass."
---

We're executing an approved plan with worker subagents, and I need the brief for phase 2 that goes to the implementer worker. Don't dispatch anything and don't read any files; print the complete brief text I'd hand the worker.

The plan (approved, autonomous run, no human in the loop):

- Repo: /home/dev/orders-api, default branch `main`. The item's worktree already exists at /home/dev/wt/orders-rate-limit on branch `feat/orders-rate-limit`. Commit authority: worker.
- Goal: per-client rate limiting on `POST /orders`, so one noisy client can no longer starve the others.
- Phase 1 [DONE]: `RateLimiter` class in `src/limits/rate_limiter.py` with unit tests.
- Phase 2 (worker, no model routing): wire `RateLimiter` into `src/api/orders.py` so a client over 100 requests a minute gets HTTP 429 with a `Retry-After` header; add tests in `tests/api/test_orders_rate_limit.py`. Acceptance: an over-limit request returns 429 with `Retry-After`; under-limit requests are unchanged; the full suite is green.
- Phase 3: document the limit in `docs/api.md`.
- Project invariants: run tests with `make test`; no issue numbers in code comments.
- Design: none.
