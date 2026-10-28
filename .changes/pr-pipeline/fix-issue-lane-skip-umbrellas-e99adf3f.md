---
bump: patch
---

### Changed

- The issue lane skips an umbrella, an `agent-ready` issue with an open sub-issue, before any model run. It keeps `agent-ready`, logs a notice naming the open sub-issues, and work-unblock's sweep re-fires it once none is open. Neither path adds `needs-human`. An issue read with no sub-issue summary lists the sub-issues rather than assuming none is open.
