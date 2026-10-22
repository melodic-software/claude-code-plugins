---
bump: minor
---

### Added

- The lost-run reconciler re-runs the failed jobs of a PR CI run that failed only from an outside outage: each failed job hit its time limit, had an install step cancelled or timed out, or lost its runner. An install step that exits with a failure, such as `npm ci` on a stale lockfile, counts as a real failure. It re-runs at most twice per run, 15 then 30 minutes after the attempt ended, only while status.npmjs.org and githubstatus.com both show no incident, and never a run with any other failure.
- fix-ci starts no model run on a head whose required-run failures are all infra while the reconciler still has a re-run left for it; once both re-runs are used, fix-ci takes the head.
