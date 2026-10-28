---
bump: minor
---

### Changed

- `/testing:run-e2e` chooses who drives each run. When the app-control plugin is installed and the app has a control skill, it hands launching, operating and capturing to `/app-control:drive` and judges what drive recorded; with app-control installed but no control skill it offers `/app-control:map create`; without app-control it suggests installing it. The person can decline any of these, and an unattended run asks nothing: it takes run-e2e's own driving and records the suggestion in its report. testing does not depend on app-control.
- run-e2e's own driving (the bundled `run` launch step, prerequisites, run config, Workspace environment, session names and teardown) moved from the skill body to `context/own-driving.md`, which loads only on that route. The entry-point chooser and the per-entry-point report line are separate sections of the body.
- `e2e_driver`, `reuse_running_instance` and `browser_driver` now apply only to run-e2e's own driving; on a run through `/app-control:drive`, the control skill supplies the tools. `recording` and `browser_mode` (`.claude/testing/e2e.md`) also apply only to own driving: drive has no headed or headless setting, and a recording on the drive route is the control skill's `video` capture.
- On the drive route each touched feature gets its own `--out` directory, so one feature's drive report does not overwrite another's.
