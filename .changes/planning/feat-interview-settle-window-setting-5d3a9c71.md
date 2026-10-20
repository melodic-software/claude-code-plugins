---
bump: minor
---

### Added

- The interview server reads its settle window from two new settings, `settleQuiet` (default 10 s, 0.5 to 60) and `settleBurst` (default 30 s, 1 to 120), resolved through the same layers as `leaseTimeout` and shown read-only in the Settings panel. The quiet window was 3 s and the burst cap 12 s, so a sweep of plain accepts woke the agent on most accepts; it now wakes once. A non-numeric or out-of-bounds value falls through to the layer below, a `settleQuiet` above `settleBurst` puts both back to the defaults, and neither stops the server.
