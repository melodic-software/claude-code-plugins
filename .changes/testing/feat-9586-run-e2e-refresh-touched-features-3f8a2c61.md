---
bump: minor
---

### Added

- `/testing:run-e2e` keeps a control skill current. After the run, each feature whose index `sources` globs match a changed file gets `/app-control:map refresh <feature id>` when app-control is installed, with `--unattended` on an unattended run. Without app-control, the report names the feature's possible drift and the refresh command in `## Next`; the run never stops or fails for it. run-e2e never edits a control skill itself.
