---
bump: minor
---

### Added

- `/verification:confirm` keeps a control skill current. When `/testing:run-e2e` ran, its refresh or drift lines carry into the report; when the live drive is split across workers, the workers skip the refresh and confirm runs it once over the merged report. When it did not, confirm calls `/app-control:map refresh <feature id>` (with `--unattended` when no one is present) for each feature whose index `sources` globs match a changed file, carrying that feature's lesson in the same call, or, without app-control, reports the drift and names the command in `## Next`. Neither the drift nor app-control's absence holds the verdict.
