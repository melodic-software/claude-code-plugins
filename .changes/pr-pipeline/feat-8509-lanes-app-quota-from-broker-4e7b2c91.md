---
bump: minor
---

### Added

- The monitoring lane reads the lanes App's own REST quota from lane runs. `request-lane-token`
  reads an optional `rate_limit` object (`remaining`, `limit` and `reset` in epoch seconds) from
  the broker's token 200 and writes an `api-budget` notice,
  `mint lanes-app core remaining=R used=U limit=L reset=<ISO>`, and a job summary line. With no
  `rate_limit` it writes nothing more; a malformed one warns `lane-token-quota-unread` and the
  step still passes. The monitor's new `lane api budget` source reads that notice from up to 10
  completed lane runs in the window and up to 10 jobs whose mint step succeeded. It reads only
  runs of this repository's own head on an event that runs the default branch's workflow code (a
  push or dispatch only on `main`), skips the test-suite runs, and leaves a trusted pr-merge run's
  merge job to the pr-merge source. Signal 2's `ceiling:lanes-app-rest` flags a reading over 90%. The
  broker half is tracked in melodic-software/azure-iac#103.
