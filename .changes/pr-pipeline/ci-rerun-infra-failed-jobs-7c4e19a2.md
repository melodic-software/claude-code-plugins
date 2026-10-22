---
bump: minor
---

### Added

- The lost-run reconciler re-runs the failed jobs of a PR CI run that failed only from an outside outage: each failed job hit its time limit, failed in an install step, or lost its runner. It re-runs at most twice per run, 15 then 30 minutes after the attempt ended, only while status.npmjs.org and githubstatus.com both show no incident, and never a run with any other failure.
- fix-ci starts no model run on a head whose required-run failures are all infra; the reconciler owns those.
