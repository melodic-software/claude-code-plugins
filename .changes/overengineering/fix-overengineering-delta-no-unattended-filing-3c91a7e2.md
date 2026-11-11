---
bump: minor
---

### Removed

- The `delta` skill's `queue_route` setting. A cycle no longer files or updates a work item through
  `work-items:track`, whose `add` action accepts no other skill's steps as authorization to file.
  A `queue_route` key left in config is ignored.

### Changed

- `delta`'s `## Queued for the human` section ends with a draft work item when the queue is not
  empty, for a human or the triage lane to file with `/work-items:track add`.
