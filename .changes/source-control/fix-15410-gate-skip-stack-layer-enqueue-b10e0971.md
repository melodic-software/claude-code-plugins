---
bump: patch
---

### Fixed

- The unattended babysit merge path no longer posts a pin comment or calls `enqueuePullRequest` on a native stack layer, which GitHub refuses on every sweep. It reads the `stack` field the pull request record it already holds carries, and holds the layer for a person, so it adds no API call.
