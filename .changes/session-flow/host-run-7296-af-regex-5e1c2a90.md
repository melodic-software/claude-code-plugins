---
bump: patch
---

### Fixed

- The `af-unknown-token-stops` eval case's `rejects-bad-token` grader now accepts the stop reply
  "`--apply-fixes` isn't an argument this skill accepts", which `/session-flow:audit-friction`
  gives, so a correct stop no longer scores 0.50.
