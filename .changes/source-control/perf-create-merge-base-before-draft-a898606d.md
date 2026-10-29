---
bump: patch
---

### Changed

- `/source-control:pull-request create` merges the base into the branch before it pushes and opens the draft when the open state resolves to `ready` and `ready`'s `base-merge` step would run, including under `create --pushed` when the worker's branch is behind. `ready`'s base merge then finds nothing to push, so the PR no longer starts a `synchronize` CI run between the `opened` and `ready_for_review` runs. A `draft` state keeps the old behavior.
