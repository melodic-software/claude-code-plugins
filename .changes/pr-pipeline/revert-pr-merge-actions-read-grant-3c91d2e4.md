---
bump: patch
---

### Changed

- The pr-merge lane token carries no Actions permission: `merge-pr`'s `activity-grants` row is gone, and a test pins that no live slot resolves an actions permission. The verdict downloads, the artifact listing, the run records and the compares stay on `GITHUB_TOKEN`, and nothing is built to fall back from them to the lane token.
