---
bump: patch
---

### Changed

- `pr-merge.yml` no longer wakes on a pull request's `edited` or `ready_for_review` event, which over a day started 200 runs that enqueued, merged and disarmed nothing. A person's ready or rename restarts their pull request's idle clock, an event run never arms, and `ci-status` already fails on a body hold; the 15-minute schedule picks up each such change. `unlabeled` stays, because `pr-feedback-dispatch.yml` starts on that run's completion.
