---
bump: major
---

### Added

- `limits.worker-job-ceiling` (default 8, at most 50): the jobs an issue run may roll over into at its time limit since a listed human last added `agent-ready`; the next stop hands the issue to a person. This repository sets 8, about 48 hours at 6 hours a job.

### Removed

- `limits.turn-cap-restarts`: a config that sets it now fails the resolve. `worker-job-ceiling` and the progress rule below replace it.

### Changed

- An issue run works across several jobs. The run job's timeout is the size's `timeout-minutes`, and its model step stops `run-minutes` (a new resolve-config output, the timeout less the minutes kept for saving) into it, so a run that outlasts a job still has its patch collected and committed to its lane branch.
- `report-outcome` decides whether a run stopped at its job's time limit from the Actions API (its run job's model step ran its whole `run-minutes`, the new `run-minutes` write-runner input), never from `lane.json`; a job or step the API does not list leaves the stop unknown, and the run hands back like `stopped`. A stop at the time limit whose own lane branch has a lanes-App tip that changes a file other than the progress note rolls over: it keeps `agent-ready` with an `outcome=timeout` marker and work-unblock restarts it, up to `worker-job-ceiling` roll-overs, then hands back with `outcome=job-ceiling`, naming the job count and the progress note's next steps. With no new commit it posts `outcome=no-progress`, removes `agent-ready` and adds `admission-deferred`, so the next sweep re-admits it through the queue without `needs-human`; a second such stop in a row hands back with `outcome=stalled`, naming both runs and the note. A stop whose patch apply-issue-patch refused hands back like `stopped`. The `pipeline/resolve-issue` status no longer names a turn-cap stop from `lane.json`. The monitoring lane's lane-stop signal reports `turn-cap`, `timeout`, `no-progress`, `job-ceiling` and `stalled` stops.
- A `split-required` dimension skip hands the issue back to intake (`needs-triage`, no escalation marker) instead of to a person.
- The `resolve-issue` activity also runs `scripts/check-lane-progress-note.sh --check`, so a done run that left its progress note, `.lane-progress.md`, opens no PR.
- A `turn-cap`, `timeout` or `job-ceiling` stop's lane branch resumes even when it is behind the default branch, since one long run continues across jobs while the default branch moves on; other resumable stops still start fresh from a branch behind it.
