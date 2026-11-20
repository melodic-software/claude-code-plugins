---
bump: patch
---

### Fixed

- The babysit merge gate no longer holds a retargeted pull request forever. Review evidence binds only on lane runs created after the newest base change, so a review read against the old base never counts, and a lane unbound as `base-retargeted` requests one whole review of the head, under the same per-head, per-pull-request and per-sweep caps as a refused re-run. Every upper stack layer GitHub retargets when the layer below merges now clears without a push.
