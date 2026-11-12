---
bump: patch
---

### Changed

- The audit skill's session-mode reference reads role labels only from the `tracker` mapping of `docs/conventions/work-items.yaml`, matching the work-items seam, which no longer reads a repo-root `.work-item-tracker.json`.
