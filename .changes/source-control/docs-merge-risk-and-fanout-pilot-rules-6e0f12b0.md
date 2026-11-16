---
bump: minor
---

### Added

- Merging after AI review now requires a lanes App pull request to carry a merge-risk rating for the pinned head. With `demote=true`, the session merges only when an owner decision covers each HIGH or CRITICAL reason, and sends any other reason to the owner.
