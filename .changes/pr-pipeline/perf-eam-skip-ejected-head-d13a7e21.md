---
bump: patch
---

### Changed

- `enable-auto-merge.mjs` skip-unchanged now keeps a head the merge queue ejected up to the cap (`merge.max-queue-ejections`): while the gate's ejection comment stands unchanged and the skip key matches, later reader runs leave it refused without reading its discussion, files and verdict again, until the head or another key input changes, `max-minutes` or `max-skips` runs out, or its refusal is due to turn into a failing status. An ejection count that could not be read is never kept.
