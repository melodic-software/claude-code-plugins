---
bump: patch
---

### Fixed

- The concurrency table's `pr-feedback-dispatch` row now matches the workflow. Its group is per
  pr-verify run (`verify-<run id>`), shared by all sweeps (`sweep`), or per reviewed head
  otherwise, and `queue: max` queues waiting runs instead of replacing them.
