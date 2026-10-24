---
bump: major
---

### Removed

- `limits.turn-cap-restarts`: a config that sets it now fails the resolve. No count bounds restarts of an issue run that stopped at its turn cap or its job's time limit; progress decides instead (Changed below).

### Changed

- An issue run works across as many jobs as it needs. The run job's timeout is the size's `timeout-minutes`, and its model step stops `run-minutes` (a new resolve-config output, the timeout less the minutes kept for saving) into it, so a run that outlasts a job still has its patch collected, committed to its lane branch and recorded as class `timeout`.
- `report-outcome` treats a `timeout` stop like a turn-cap stop and decides on progress, read from the API: when the stopped job's own lane branch exists with a lanes-App tip it keeps `agent-ready` with an `outcome=turn-cap` or `outcome=timeout` marker and work-unblock restarts it, with no count; with no new commit it posts `outcome=no-progress`, adds `admission-deferred` and removes `agent-ready`, so the next sweep re-admits it through the queue, never with `needs-human`. A stop whose patch apply-issue-patch refused hands back like `stopped`. The monitoring lane's lane-stop signal reports `no-progress` stops instead of `turn-cap` ones.
- A `split-required` dimension skip hands the issue back to intake (`needs-triage`, no escalation marker) instead of to a person.
- The `resolve-issue` activity also runs `scripts/check-lane-progress-note.sh --check`, so a done run that left its progress note, `.lane-progress.md`, opens no PR.
- A `turn-cap` or `timeout` stop's lane branch resumes even when it is behind the default branch, since one long run continues across jobs while the default branch moves on; other resumable stops still start fresh from a branch behind it.
