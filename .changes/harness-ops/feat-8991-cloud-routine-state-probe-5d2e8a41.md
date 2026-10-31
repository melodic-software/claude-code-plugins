---
bump: minor
---

### Added

- `/harness-ops:behavior-probes` has a `cloud-routine/state-read-back-next-run` case. It uses
  `/schedule` to create a one-off cloud routine, runs it once at once and lets the scheduled fire be
  the second run, then judges whether the second run read back the state record the first run
  posted to an issue comment. Record 19 holds the 2026-10-31 hand run on Claude Code 2.1.314: the
  read-back passed, the shell inside the run is in UTC, and the session's own date zone stays open.
- Cases take an optional `timeout` (seconds, in place of `--timeout`) and an optional `explicit`
  flag. A live run skips an `explicit` case unless `--case` names it, because the case creates a
  routine on the operator's account and posts public comments.
