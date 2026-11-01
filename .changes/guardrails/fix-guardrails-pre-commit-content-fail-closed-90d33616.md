---
bump: patch
---

### Fixed

- The pre-commit content check now fails the commit, with a message saying the scan did not finish, when a text tool it runs (awk, grep, sed, sort or cut) fails. A crashed awk run used to leave the staged text unscanned and the commit passing.
- The pre-commit content check no longer takes over 30 seconds on a single large added file: its whitespace-only test ran in time that grew with the square of the file's size. A 1,300-file merge now takes about 30 seconds instead of about 100.
