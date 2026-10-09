---
bump: patch
---

### Changed

- **The vendored transcript reader is regenerated** from session-flow's copy: it gains permission-outcome parsing and counts a stream-json `result` record as a known type. Nothing in performance calls the new functions.
