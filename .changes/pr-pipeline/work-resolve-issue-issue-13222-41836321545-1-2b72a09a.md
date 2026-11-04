---
bump: minor
---

### Added

- The monitoring lane's signal 13, `lane holds`, counts the green runs that held on a fault with
  only a notice: work-resolve-issue's fault stops whose retries were all faults, work-unblock's
  unreadable listings, and pr-refine's failed `fix-docs` reads. A lane with
  `monitor.lane-holds.threshold` held runs or more (default 4) in the last
  `monitor.lane-holds.window-hours` (default 24) raises the signal's rolling issue, which only
  notifies. The new optional `monitor` section of `pr-pipeline.yaml` holds both values, and the
  lane carries its held runs from one hourly run to the next in its job reads artifact.
