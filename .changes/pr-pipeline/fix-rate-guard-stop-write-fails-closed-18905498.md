---
bump: patch
---

### Fixed

- The shell rate guard ends the step when it cannot record a stop (no space or no permission for `$RUNNER_TEMP/api-budget`), with an error naming the pool, and refuses every later call in that shell, so no call reaches an exhausted pool unrecorded. The Node guard names a stop it could not record in its error line.
- The shell and Node stop-file readers take only lines shaped `<pool> <1-12 digits>`, alike, so a fragment a short write left spoils only the line it runs into; `rate-guard.vectors.json` pins the reader cases for every port.
