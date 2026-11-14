---
bump: minor
---

### Changed

- `/toolchain:lint` and `/toolchain:check` name each changed text file outside every ecosystem on an
  `Outside every ecosystem` line below the table, instead of skipping it silently. A binary file
  stays quiet, a file a running cross-cutting pass covers is not named by `/toolchain:lint`, and the
  line changes no Status or Overall line.
