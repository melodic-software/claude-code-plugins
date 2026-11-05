---
bump: patch
---

### Fixed

- poll the found capture run, record a missing capture as blocked, cap capture retention at 30

  find-capture lists the capture workflow's runs only until the capture run
  shows up, then reads that run's own record (GET actions/runs/{id}) every
  3 minutes, re-checking its identity, with the last read at the 35-minute
  bound: a full wait costs 13 calls instead of 36.

  With merge.verify-capture.app set, every miss (no run, a run that ended
  other than success, a run still going at the bound, no artifact, an API
  failure, a failed download) now reaches the verdict as capture: blocked
  with a reason find-capture builds from a fixed code, a run id and a run
  conclusion; no-app now means only that the app is unset. A miss that
  cannot change (a red run, no artifact, a malformed input) rides the
  existing carry output, pattern-checked like the ids, so the later judge
  jobs record the same reason without searching again; after a miss that
  can change (no run yet, still running, a failed read) they search again.
  A red capture run's artifact is not read.

  merge.verify-capture.retention-days now accepts 1 to 30, so the
  pr-capture-* retention row's 30 days is the true upper bound.

  Refs: #12232
