---
bump: patch
---

### Fixed

- `report-stop-status` posts no failing `pr-unblock/address-feedback` status for a `feedback-publish-failed` whose lane token was refused in a way a retry takes the head on (workflow-modified, which the feedback sweep sends again, or a transient broker failure, which pr-merge re-fires); it reads the run's jobs and annotations with `actions: read` and `checks: read`
