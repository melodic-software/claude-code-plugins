---
bump: minor
---

### Changed

- Every reader of the hosted review lanes' verdicts (ci-status's review-lanes and cost-hold steps, merge-holds.mjs, clear-escalations.mjs, feedback-dispatch.mjs and the lost-run reconciler's pending check) also accepts a run of the caller's `workflow_run` lane (`pr-review-hosted-lane.yml`, `pr-review-security-hosted-lane.yml`). It finds the run through the index check run named for that workflow on the head and binds it only on its own record: path, event `workflow_run`, head branch `main`, both repositories, and the run-name `<name> #<pull request> <head sha>`. At a head with a bound lane run, that run is read instead of the head's `pull_request` run. No lane run exists yet, so verdicts are unchanged; each reader makes one more read per head and lane.
