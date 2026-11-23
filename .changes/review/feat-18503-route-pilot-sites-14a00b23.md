---
bump: minor
---

### Added

- route two pilot steps through the route caller contract

  /review:fanout's leaf reviewer dispatch and /codebase-health:audit's
  per-file discovery fan-out now point at the caller contract of
  /multi-agent:route (if enabled); otherwise they run here as before.
