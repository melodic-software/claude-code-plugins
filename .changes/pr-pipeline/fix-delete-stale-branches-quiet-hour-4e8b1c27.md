---
bump: patch
---

### Fixed

- Stale-branch cleanup (`maintenance-delete-stale-branches.yml`) moves from 06:17 to 13:17 UTC, the quietest hour of job-token calls measured, out of the busy overnight hours where its calls added to a `GITHUB_TOKEN` breaker trip.
