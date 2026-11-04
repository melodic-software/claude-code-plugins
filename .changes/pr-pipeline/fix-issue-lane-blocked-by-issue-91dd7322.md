---
bump: patch
---

### Fixed

- work-resolve-issue routes a `blocked-by-issue` stop back through intake triage once (`intake`,
  `retries: 1` in `stop-routes.json`) instead of to the owner. Its comment names the first `#<n>`
  in the run's reason outside the quoted run words, so intake records that issue on its
  `Blocked by:` line as a blocked-by edge and admission waits for it to close.
