---
bump: patch
---

### Fixed

- `check-trusted-trigger` matches the re-runner by account id on every path instead of by login: it reads this run's own record (`GET /actions/runs/{run_id}`) and checks `triggering_actor.id` against the trusted-actor list, so a released login re-registered by someone else no longer passes. A failed or malformed read, or a record for another run or attempt, stops with `untrusted-rerunner`. The App-label re-runner must still be the listed lanes App or a listed human. `pr-unblock-dispatch.yml` now passes the job token to the gate so it can read its run.
