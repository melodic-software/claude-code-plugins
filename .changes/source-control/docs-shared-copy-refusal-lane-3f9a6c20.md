---
bump: patch
---

### Changed

- `babysit_merge.py` no longer says no lane acts on a `shared-copy-sources-changed` refusal: on a lanes App pull request, pr-unblock's `sync-shared-copies` activity merges the base and regenerates the copies.
