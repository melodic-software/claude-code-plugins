---
bump: patch
---

### Fixed

- pr-merge.yml's full-run dispatch no longer waits out a rate limit and sends again: a rate-limited 403 or 429 fails the step red, naming the pool and the reset, and the candidate listing fails red on a rate limit instead of retrying it. enable-auto-merge's resend is pinned by a test never to resend an arm GitHub answered with 403 or 429.
