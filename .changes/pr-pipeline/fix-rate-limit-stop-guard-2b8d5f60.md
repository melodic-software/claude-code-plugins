---
bump: patch
---

### Fixed

- pr-merge.yml's full-run dispatch no longer waits out a rate limit and sends again: a rate-limited 403 or 429 fails the step red, naming the pool and the reset, and the candidate listing fails red on a rate limit instead of retrying it. enable-auto-merge's resend is pinned by a test never to resend an arm GitHub answered with 403 or 429. When a gate reader it starts (the per-pull-request verifier read or the lane-room read) exits 75 on a rate limit, enable-auto-merge sends no further read, arm, disarm or note that run and fails red with the guard's error naming the pool and the reset.
