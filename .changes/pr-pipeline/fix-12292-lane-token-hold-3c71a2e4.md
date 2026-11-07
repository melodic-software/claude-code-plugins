---
bump: patch
---

### Fixed

- pr-merge's two lane-token steps hold green on a GitHub rate limit the request's 1-minute retry
  budget could not wait out (`request-lane-token` `rate-limit-hold-ok`, a `Lane token hold`
  notice and `skip-reason` `rate-limited`), instead of ending red; every step that uses the token
  skips. Other callers keep the red. Monitor signal 13 counts the hold under `lane-hold:pr-merge`
  with the fixed reason `lane token rate-limited`.
- pr-review-main's legs take the trusted-text job's shared read only while it is at most
  `SHARED_TEXT_MAX_AGE_MINUTES` (20) old, so a subscription or fallback leg that starts later
  reads the PR text again.
