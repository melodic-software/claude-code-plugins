---
bump: patch
---

### Fixed

- work-unblock no longer adds `needs-human` when an issue's limit and funding stops reach `limits.limit-stops-per-issue`. That cap is a safety limit, so the issue takes the issue lane's `fail` route: the lanes App comments with an `<!-- work-resolve-issue outcome=failed run=<run id> -->` marker naming the stopped run, removes `agent-ready` and adds no label. The maintenance monitor's signal 9 now reports `outcome=failed` as `lane-stop:failed`, and a person's new `agent-ready` resumes the stopped run's branch. A sweep that finds a failed marker newest with `agent-ready` still on removes the label.
- A funding stop with no regain date (no credit or a disabled key) no longer waits for a person to restart it: work-unblock restarts it `limits.fallback-reset` hours after the stop, as it does a limit stop with no reset, counted toward `limits.limit-stops-per-issue`.
