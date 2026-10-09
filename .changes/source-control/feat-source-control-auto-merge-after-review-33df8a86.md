---
bump: minor
---

### Changed

- `pull-request` merges or enqueues a PR without asking only when it reads `CLEAN` and the AI review checks, matched by exact name, have passed on the head commit pinned with `--match-head-commit`, in a melodic-software repository whose live base-branch ruleset requires `ci-status`. Behind a merge queue it passes no strategy flag and waits until the PR merges or leaves the queue. It never arms auto-merge and never passes `--admin`, `--merge` or `--rebase`. A PR that changes CI workflows, permission or agent-instruction configuration still merges only when the user names it. The merge-queue case no longer routes to the async merge API.
