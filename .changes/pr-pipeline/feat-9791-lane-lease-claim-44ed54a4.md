---
bump: minor
---

### Changed

- The read runner's `broker-check` job holds `issues: write`. In issue mode, after the broker's allow, it claims the issue with a lease comment held by the lanes App identity before any model turn; a live older lease makes the run exit `already-leased` with no model turn. A new `lease-release` job releases the lease once every other job of the run ends, unless the caller passes `caller-releases-lease: true`. `work-resolve-issue.yml` does, and its `release-lease` job releases the lease after the PR opens and the outcome is reported, so no local loop takes the issue in between.
