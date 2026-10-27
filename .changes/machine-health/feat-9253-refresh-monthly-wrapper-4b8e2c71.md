---
bump: minor
---

### Changed

- **`/machine-health:setup check` offers to refresh a stale monthly wrapper copy.** When step 6 finds the copy in `<StateBase>/scheduler/` differs from the plugin's template, it offers the refresh and, only on the owner's yes, rewrites the copy alone (not the task) and reports whether it is now current. A plugin update no longer leaves the scheduled run on an old wrapper until `schedule` is rerun.

### Fixed

- **`Install-MonthlyRun` writes the wrapper copy atomically.** It writes through `Write-StateFile` (a temp file in the same folder, then a swap) instead of copying in place, so an interrupted write leaves the old copy or the new one, never a partial file.
