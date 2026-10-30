---
bump: minor
---

### Changed

- The read runner's `broker-check` job holds `issues: write`. In issue mode, after the broker's allow, it claims the issue with a lease comment held by the lanes App identity before any model turn; a live older lease makes the run exit `already-leased` with no model turn. A new `lease-release` job releases the lease once every other job of the run ends.
