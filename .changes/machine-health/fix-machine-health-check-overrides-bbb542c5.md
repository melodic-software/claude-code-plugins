---
bump: patch
---

### Fixed

- `Restart-StoppedService` now honors `approvals.json` `check_overrides.services.service_exclusions`: a stopped service whose name matches an entry (exact name, any case) is never started and gets no attempt record, and the run log records the skip. The key was documented before but nothing read it.
- The `approvals.json` schema description now says the file is written by `/machine-health:setup` and the first-run migration, not by hand.

### Removed

- `check_overrides.event-log-errors.noise_allowlist` is no longer documented: no check ever read it. The schema still accepts it, now described as ignored, so an existing file that holds it keeps validating.
