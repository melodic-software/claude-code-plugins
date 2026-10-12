---
bump: minor
---

### Added

- `babysit-postmerge.sh` checks every merge since a floor that a human did not enqueue (a null or non-human queue-event `actor` or `enqueuer`, Dependabot and sync-App merges included) against the scheduled and dispatched full `pr-require-checks` runs, the silent-revert canary, and a read-back of the pinned head, and prints a JSON verdict; a merge with no queue event is reported as `unqueued-merge`. A red full run counts only after one `rerun-failed-jobs` by the agent identity: red again is a failure, green a flake. Only a merge the agent identity enqueued needs the read-back; any other verifies on the dispatch and canary runs. It is read-only unless `--remediate`, which triggers that re-run, dispatches one full run on the branch tip when an unverified merge has no identity dispatch run covering it, dequeues the agent identity's merge-queue entries, and files a demotion issue carrying `git revert <merge-sha>` (or comments on the existing one). The babysit loop runs it at every cycle start and merges nothing that cycle unless it exits 0.
