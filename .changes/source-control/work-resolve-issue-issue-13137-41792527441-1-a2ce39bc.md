---
bump: minor
---

### Added

- `/source-control:pull-request conflicts --ci --unattended`: an unattended conflict mode for the pr-unblock lane, which still calls `/source-control:resolve-conflicts ci` until its config switches over. It reads the runner's `conflicts.json`, resolves each conflicted path in place, runs no command, never edits a path under `.github/workflows/`, and leaves a path it cannot resolve with its markers, which hands the run to a person.

### Changed

- `/source-control:pull-request`'s base-merge step (`ready`, §2.5.2) now holds the conflict discipline: map the stop, recover both sides' intent, compose by default, sweep for semantic conflicts, and verify. It escalates only when the two intents cannot both hold. The plugin version-bump collision rule moved there too, and `create`, `push-branch.sh`'s exit-4 message, `/source-control:babysit-loop` and `/source-control:babysit-prs` now point to it instead of `/source-control:resolve-conflicts`.
