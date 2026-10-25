---
bump: patch
---

### Fixed

- The shell rate guard ends the step when it cannot record a stop (no space or no permission for `$RUNNER_TEMP/api-budget`), with an error naming the pool, and refuses every later call in that shell, so no call reaches an exhausted pool unrecorded. From a subshell its errors go to the step's own stderr, so they reach the log when a caller such as ci-status's `gh_read` holds the call's stderr in a file. The Node guard names a stop it could not record in its error line.
- The shell and Node stop-file readers take only lines shaped `<pool> <1-12 digits>`, alike, so a fragment a short write left spoils only the line it runs into; `rate-guard.vectors.json` pins the reader cases for every port. Both guards cap a stop at the largest 12-digit second, so a huge `retry-after` still writes a stop the readers take.
