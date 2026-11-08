---
bump: patch
---

### Changed

- Issue-status and hold readers accept `needs-owner-decision` and `status: needs-decision`, and `needs-reporter-info` and `status: needs-info`, as the same hold, so those labels can be renamed without breaking admission, re-entry, refinement or the sweeps. A reader that takes a hold off an issue removes whichever name the issue carries.

### Removed

- The `wontfix` refuse label and the `source: lane-sweep` and `source: factory-monitor` labels, which nothing reads, and the `cadence:` labels the recurring filer applied.
