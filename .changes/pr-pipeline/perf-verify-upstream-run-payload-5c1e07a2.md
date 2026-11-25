---
bump: patch
---

### Changed

- pr-verify's resolver (`resolve-pr.mjs`) and `upstream-jobs.mjs` take the pr-require-checks run from the `workflow_run` event payload instead of reading it back, and read the jobs of that payload's attempt (`/actions/runs/{id}/attempts/{n}/jobs`) instead of the run's latest jobs, so each pr-verify run spends one GitHub API call fewer and a re-run started since cannot change the run or the jobs judged. A payload missing a checked field, or with no attempt number, skips as `not-a-passing-run`; a missing or unreadable payload fails the step. The lost-run reconciler passes the run it already listed to the resolver, so its spec checks spend one call fewer each.
