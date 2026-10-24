---
bump: major
---

### Added

- `limits.worker-active-hours` (default 48, at most 336) and `limits.worker-wall-days` (default 7, at most 30): an issue run's model run time and wall-clock time since the run of work began. The stop or wait that reaches either hands the issue to a person with the progress note. This repository sets 48 and 7.
- The `lane: waiting-on-usage` label marks an issue run that is waiting for its usage limit to reset; report-outcome adds it only once the repository has it.

### Removed

- `limits.turn-cap-restarts`: a config that sets it now fails the resolve. The ceilings above and the progress rule below replace it.

### Changed

- An issue run works across many jobs of about an hour. This repository sets each size's `timeout-minutes` to 75. The model step stops `run-minutes` into the job (a new resolve-config output: the timeout less the minutes kept for saving), so each job's patch and progress note reach its lane branch, and an outage loses at most one job.
- `report-outcome` decides from the Actions API whether a run stopped at its job's time limit (its run job's model step ran its whole `run-minutes`, the new `run-minutes` write-runner input), never from `lane.json`. A job or step the API does not list leaves the stop unknown, and the run hands back like `stopped`. Each stop or wait marker carries `ran=<minutes>`, the job's model-step minutes. A stop at the time limit whose own lane branch has a lanes-App tip that changes a file other than the progress note rolls over: it keeps `agent-ready` with an `outcome=timeout` marker, and work-unblock restarts it. With no new commit it posts `outcome=no-progress`, removes `agent-ready` and adds `admission-deferred`, so the next sweep re-admits it through the queue without `needs-human`. A second such stop in a row hands back with `outcome=stalled`, naming both runs and the note. Reaching either ceiling hands back with `outcome=active-ceiling` or `outcome=wall-ceiling`. A stop whose patch apply-issue-patch refused hands back like `stopped`. The `pipeline/resolve-issue` status no longer names a turn-cap stop from `lane.json`.
- A usage-limit stop on an issue run is a wait. It never adds `needs-human` and no longer counts toward `limits.limit-stops-per-issue`, which now counts funding stops only. work-unblock restarts it at the reset and takes the waiting label off.
- The monitoring lane's lane-stop signal reports `turn-cap`, `timeout`, `no-progress`, `active-ceiling`, `wall-ceiling` and `stalled` stops.
- A `split-required` dimension skip hands the issue back to intake (`needs-triage`, no escalation marker) instead of to a person.
- The `resolve-issue` activity also runs `scripts/check-lane-progress-note.sh --check`, so a done run that left its progress note, `.lane-progress.md`, opens no PR.
- A `turn-cap`, `timeout`, `active-ceiling` or `wall-ceiling` stop's lane branch resumes even when it is behind the default branch, since one long run continues across jobs while the default branch moves on. Other resumable stops still start fresh from a branch behind it.
