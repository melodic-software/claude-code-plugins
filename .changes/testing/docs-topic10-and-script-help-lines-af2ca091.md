---
bump: patch
---

### Changed

- `/testing:write`: on a bug fix, the first red runs against the existing code and fails on the wrong behavior, not on a missing symbol. When the skill states the interface it assumes, it adds one line on what a test at that seam catches and what it misses.
