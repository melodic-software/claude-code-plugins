---
bump: patch
---

### Fixed

- verify-cap.mjs runs the FAIL-cap reader with `BABYSIT_VERIFY_NO_INCREMENTAL_WAITS=1`. Before this,
  the 15 s and 30 s waits after a missed incremental read, plus the whole listing after them, could
  run past the reader's 2-minute kill. verify-cap reads a killed reader as not the cap, so a round
  could start on a pull request that was already at `verify:repeated-fail`.
- The log-api-budget action's `calls` output reports `unknown` in place of an empty count when the
  job has no api-calls line to read (no `RUNNER_TEMP`).
