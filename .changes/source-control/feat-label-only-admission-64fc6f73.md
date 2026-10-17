---
bump: patch
---

### Changed

- The pr-merge lane reads no issue comment or trusted-actor list for a lane pull request's closing issue: the issue lane admits on the `agent-ready` label alone, so the merge gate checks no admission marker.
