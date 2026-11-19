---
bump: minor
---

### Added

- `merge.queue-ejection-infra-causes` (default every cause: `rate-limit`, `read-floor`, `verify-unreadable`, `kill-switch`, `lost-runner`, `main-red`) names the infra causes a merge-queue removal is not counted toward `merge.max-queue-ejections` for. A removal is excused only when every failed job of its merge-group run failed on those causes alone, or failed on main's run of that workflow at the time too; the budget causes and `main-red` excuse it only after their reset, or an hour. Before, only a run whose `CI Status` alone failed on a rate limit was excused, so verify:unreadable read-floor refusals, kill-switch stops and rate limits in other jobs held #17253, #17325, #17340, #17359 and #17417 at the cap with `pr-merge/unarmed` until a push. Each excused removal gets a `::notice title=queue-ejection::` line.
