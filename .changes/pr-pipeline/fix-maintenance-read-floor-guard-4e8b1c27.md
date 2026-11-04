---
bump: patch
---

### Fixed

- `maintenance-delete-stale-branches.yml` and `maintenance-reconcile-lost-runs.yml` now read and change nothing while the `GITHUB_TOKEN` pool is under `limits.api` github-token `read-floor` of its planned budget, or the pool cannot be read. The check is one counted read in the new `.github/actions/check-read-floor` action, and it applies on every event. Stale-branch cleanup moves from 06:17 to 13:17 UTC, the quietest hour of job-token calls measured.
