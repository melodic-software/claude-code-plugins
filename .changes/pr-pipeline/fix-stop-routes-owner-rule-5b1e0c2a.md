---
bump: minor
---

### Changed

- **The issue lane sends only intent, design, security and cost stops to a person.** Every `hold` row in `stop-routes.json` now names its `class`, and a test fails any hold row whose class is not one of those four. A stop with no code retries once and then fails; `split-required` takes a new `intake` route that removes `agent-ready`, `status: ready` and `admission-deferred`, so the triage sweep sends the issue back through intake, whose split files its sub-issues (owner Q93). The triage sweep counts the lane's `outcome=intake` comment as a hand-back that starts a new dispatch cycle.

### Added

- **`blocked-by-pr` stop code and `wait` route.** A run that waits on an open pull request names it; the lane keeps `agent-ready` with an `outcome=wait pr=<n>` marker, and the work-unblock sweep restarts the issue once that pull request merges or closes, its waits counted against `limits.stop-retries` apart from its retries. A pull request that is not open retries instead.
- **`already-done` and `report-delivered` stop codes and `close` route.** The lane closes the issue as completed: `already-done` only once the cited merged pull request or commit is on the default branch, and `report-delivered` only on a `work-class: read-only` issue the run committed nothing for, posting the run's summary as the report. Either retries otherwise.
