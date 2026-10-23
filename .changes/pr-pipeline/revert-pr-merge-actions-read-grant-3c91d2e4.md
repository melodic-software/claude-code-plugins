---
bump: patch
---

### Changed

- The pr-merge lane token no longer carries Actions read: `merge-pr`'s `activity-grants` row is gone, and a test pins that no live slot resolves an actions permission. Every Actions read in pr-merge stays on `GITHUB_TOKEN`, with no fallback to the lane token.
